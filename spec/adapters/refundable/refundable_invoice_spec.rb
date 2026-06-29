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
end
