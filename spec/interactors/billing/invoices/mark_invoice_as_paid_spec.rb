require "rails_helper"

RSpec.describe Billing::Invoices::MarkInvoiceAsPaid, type: :interactor do
  let!(:invoice) { create(:invoice, status: 'open') }
  let!(:operator) { create(:operator) }

  describe "#call" do
    context "when invoice is open and has a location" do
      before do
        allow(invoice.location).to receive(:mark_invoice_paid).and_return(true)
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

    context "when invoice location is missing" do
      before do
        allow(invoice).to receive(:location).and_return(nil)
      end

      it "fails with a missing location message" do
        result = described_class.call(invoice: invoice, operator: operator)

        expect(result).to be_failure
        expect(result.message).to eq('Invoice location is missing')
      end
    end
  end
end
