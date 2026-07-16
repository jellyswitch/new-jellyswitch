require "rails_helper"

RSpec.describe Billing::Invoices::MarkInvoiceAsPaid, type: :interactor do
  let!(:invoice) { create(:invoice, status: 'open') }
  let!(:operator) { create(:operator) }

  describe "#call" do
    context "when invoice is open and has a location" do
      before do
        allow_any_instance_of(Location).to receive(:mark_invoice_paid).and_return(true)
        allow(Billing::Invoices::AddCreditsToSubscribable).to receive(:call).and_return(double(success?: true))
      end

      it "marks the invoice as paid" do
        result = described_class.call(invoice: invoice, operator: operator)

        expect(result).to be_success
        expect(invoice.reload.status).to eq('paid')
      end
    end

    context "when invoice is already paid" do
      before do
        invoice.update(status: 'paid')
      end

      it "fails with a descriptive message" do
        result = described_class.call(invoice: invoice, operator: operator)

        expect(result).to be_failure
        expect(result.message).to eq('Invoice is already paid.')
      end

      it "does not call Stripe" do
        expect(invoice.location).not_to receive(:mark_invoice_paid)

        described_class.call(invoice: invoice, operator: operator)
      end
    end

    context "when Stripe reports the invoice as voided" do
      # Regression: mark_invoice_paid used to swallow this error and return
      # false, so the caller marked a Stripe-voided invoice paid locally.
      before do
        # Must have a location + stripe_invoice_id so the caller takes the
        # Stripe branch (not the local-only fallback).
        invoice.update_columns(location_id: create(:location).id, stripe_invoice_id: 'in_voided')
        allow_any_instance_of(Location).to receive(:mark_invoice_paid)
          .and_raise(Stripe::InvalidRequestError.new("This invoice is void", nil))
      end

      it "fails and does NOT mark the invoice paid" do
        result = described_class.call(invoice: invoice, operator: operator)

        expect(result).to be_failure
        expect(result.message).to match(/voided or marked uncollectible/i)
        expect(invoice.reload.status).to eq('open')
      end
    end

    context "when invoice location is missing" do
      before do
        allow(invoice).to receive(:location).and_return(nil)
      end

      it "marks the invoice as paid locally without calling Stripe" do
        result = described_class.call(invoice: invoice, operator: operator)

        expect(result).to be_success
        expect(invoice.reload.status).to eq('paid')
      end
    end
  end
end
