require "rails_helper"

RSpec.describe Refundable::RefundableInvoice do
  let!(:invoice) { create(:invoice, status: 'paid') }
  let(:refundable_invoice) { described_class.new(invoice) }
  let(:stripe_refund) { double("Stripe::Refund", id: "re_123") }

  describe "#cancel" do
    context "when invoice has not been refunded" do
      before do
        allow(invoice.location).to receive(:create_stripe_refund).and_return(stripe_refund)
      end

      it "creates a Stripe refund and local refund record" do
        refundable_invoice.cancel

        expect(invoice.location).to have_received(:create_stripe_refund).with(refundable_invoice, nil, amount: invoice.amount_due)
        expect(invoice.refunds.count).to eq(1)
        expect(invoice.refunds.first.stripe_refund_id).to eq("re_123")
        expect(invoice.refunds.first.amount).to eq(invoice.amount_due)
      end

      it "updates the invoice status to refunded" do
        refundable_invoice.cancel

        expect(invoice.reload.status).to eq('refunded')
      end
    end

    context "when invoice is already refunded" do
      before do
        invoice.refunds.create(amount: invoice.amount_due, stripe_refund_id: "re_existing")
      end

      it "returns early without calling Stripe" do
        expect(invoice.location).not_to receive(:create_stripe_refund)

        result = refundable_invoice.cancel

        expect(result).to eq(true)
      end
    end

    # Local state can drift from Stripe when a charge is refunded out-of-band —
    # almost always a refund issued directly in the Stripe Dashboard, which we
    # don't sync via webhook. The local `refunded?` guard (refunds.length > 0)
    # then misses it, so a "Refund" click reaches Stripe and gets
    # `charge_already_refunded`. We should reconcile, not blow up.
    context "when the Stripe charge was already refunded out-of-band (local state stale)" do
      let(:already_refunded_error) do
        Stripe::InvalidRequestError.new(
          "Charge ch_123 has already been refunded.", nil, code: "charge_already_refunded"
        )
      end

      before do
        allow(invoice.location).to receive(:create_stripe_refund).and_raise(already_refunded_error)
      end

      it "does not raise — reconciles to the already-refunded end state" do
        expect { refundable_invoice.cancel }.not_to raise_error
      end

      it "returns true (success)" do
        expect(refundable_invoice.cancel).to eq(true)
      end

      it "marks the invoice refunded and records a local refund row" do
        refundable_invoice.cancel

        expect(invoice.reload.status).to eq("refunded")
        expect(invoice.refunds.count).to eq(1)
        expect(invoice.reload.refund_amount_in_cents).to eq(invoice.amount_due)
      end

      it "is idempotent on a second click (local guard now short-circuits)" do
        refundable_invoice.cancel
        expect(invoice.location).to receive(:create_stripe_refund).never
        expect(refundable_invoice.cancel).to eq(true)
        expect(invoice.refunds.count).to eq(1)
      end
    end

    context "when Stripe raises a non-already-refunded error" do
      let(:other_error) do
        Stripe::InvalidRequestError.new("No such charge: ch_123", nil, code: "resource_missing")
      end

      before do
        allow(invoice.location).to receive(:create_stripe_refund).and_raise(other_error)
      end

      it "re-raises (real failures must still surface)" do
        expect { refundable_invoice.cancel }.to raise_error(Stripe::InvalidRequestError)
        expect(invoice.reload.status).to eq("paid")
        expect(invoice.refunds.count).to eq(0)
      end
    end
  end

  # Used by the charge.refunded webhook (Webhooks::ChargeRefunded) to sync a
  # refund that already happened on Stripe — typically a Dashboard refund — back
  # onto the local Invoice. Must be idempotent across the 2-3 Stripe events that
  # a single refund fires (charge.refunded, refund.created, charge.refund.updated).
  describe "#reconcile_refund!" do
    it "records a refund row (id + amount) and marks the invoice refunded" do
      refundable_invoice.reconcile_refund!(amount_cents: 1000, stripe_refund_id: "re_abc")

      expect(invoice.reload.status).to eq("refunded")
      expect(invoice.refunded_at).to be_present
      expect(invoice.refund_amount_in_cents).to eq(1000)
      expect(invoice.refunds.count).to eq(1)
      expect(invoice.refunds.first.stripe_refund_id).to eq("re_abc")
      expect(invoice.refunds.first.amount).to eq(1000)
    end

    it "returns true" do
      expect(refundable_invoice.reconcile_refund!(amount_cents: 1000, stripe_refund_id: "re_abc")).to eq(true)
    end

    it "is idempotent — a repeat event with the same refund id adds no row" do
      refundable_invoice.reconcile_refund!(amount_cents: 1000, stripe_refund_id: "re_abc")
      first_refunded_at = invoice.reload.refunded_at

      refundable_invoice.reconcile_refund!(amount_cents: 1000, stripe_refund_id: "re_abc")

      expect(invoice.reload.refunds.count).to eq(1)
      expect(invoice.refunded_at).to eq(first_refunded_at)
    end

    it "backfills the real Stripe id onto an amount-only placeholder row" do
      # #548's already-refunded path (or a charge.refunded with no inline refund
      # id) leaves a row with a nil stripe_refund_id; a later refund.created
      # carries the exact id and should stamp it, not create a duplicate.
      invoice.refunds.create(amount: 1000, stripe_refund_id: nil)

      refundable_invoice.reconcile_refund!(amount_cents: 1000, stripe_refund_id: "re_real")

      expect(invoice.reload.refunds.count).to eq(1)
      expect(invoice.refunds.first.stripe_refund_id).to eq("re_real")
    end

    it "works when no refund id is available (amount-only reconcile)" do
      refundable_invoice.reconcile_refund!(amount_cents: 1000)

      expect(invoice.reload.status).to eq("refunded")
      expect(invoice.refunds.count).to eq(1)
      expect(invoice.refunds.first.stripe_refund_id).to be_nil
    end

    it "reconciles an invoice that is already marked refunded without duplicating" do
      invoice.refunds.create(amount: 1000, stripe_refund_id: "re_abc")
      invoice.update(status: "refunded", refunded_at: 1.day.ago, refund_amount_in_cents: 1000)
      original_refunded_at = invoice.reload.refunded_at

      refundable_invoice.reconcile_refund!(amount_cents: 1000, stripe_refund_id: "re_abc")

      expect(invoice.reload.refunds.count).to eq(1)
      expect(invoice.refunded_at).to be_within(1.second).of(original_refunded_at)
    end
  end
end
