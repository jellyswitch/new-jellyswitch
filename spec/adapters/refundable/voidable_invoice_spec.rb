require "rails_helper"

RSpec.describe Refundable::VoidableInvoice do
  let!(:invoice) { create(:invoice, status: 'open', stripe_invoice_id: 'in_123') }
  let(:voidable) { described_class.new(invoice) }

  def stub_stripe_status(status)
    allow(invoice.location).to receive(:retrieve_stripe_invoice)
      .and_return(double("Stripe::Invoice", status: status, delete: true, void_invoice: true))
  end

  describe "#cancel" do
    it "voids an open Stripe invoice and marks it void locally" do
      stub_stripe_status('open')
      voidable.cancel
      expect(invoice.reload.status).to eq('void')
    end

    it "deletes a draft Stripe invoice and marks it void locally" do
      stub_stripe_status('draft')
      voidable.cancel
      expect(invoice.reload.status).to eq('void')
    end

    context "when Stripe already collected the invoice (status: paid)" do
      # Regression: this used to hit no case branch yet still set local status
      # to 'void' — dropping real collected revenue from the books with no
      # refund. Must refuse instead.
      it "raises and leaves the local status untouched (no silent void)" do
        stub_stripe_status('paid')
        expect { voidable.cancel }.to raise_error(/paid.*refund/i)
        expect(invoice.reload.status).to eq('open')
      end
    end
  end
end
