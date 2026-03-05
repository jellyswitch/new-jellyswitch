require "rails_helper"

RSpec.describe Refundable::RefundableInvoice do
  let!(:invoice) { create(:invoice, status: 'paid') }
  let(:refundable_invoice) { described_class.new(invoice) }
  let(:stripe_refund) { double("Stripe::Refund", id: "re_123") }

  describe "#cancel" do
    context "when invoice has not been refunded" do
      before do
        allow(invoice.location).to receive(:create_stripe_refund).with(refundable_invoice).and_return(stripe_refund)
      end

      it "creates a Stripe refund and local refund record" do
        refundable_invoice.cancel

        expect(invoice.location).to have_received(:create_stripe_refund).with(refundable_invoice)
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
  end
end
