require "rails_helper"

RSpec.describe Billing::Invoices::ChargeInvoice, type: :interactor do
  include ActiveJob::TestHelper

  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }
  let(:user) { create(:user, operator: operator, email: "buyer@example.com") }
  let(:invoice) { create(:invoice, operator: operator, location: location, billable: user, amount_due: 4000, status: "open") }

  def charge
    described_class.call(invoice: invoice, operator: operator)
  end

  context "when the charge succeeds" do
    before { allow_any_instance_of(Location).to receive(:charge_invoice).and_return(true) }

    it "marks the invoice paid and emails a receipt" do
      expect {
        expect(charge).to be_success
      }.to have_enqueued_mail(UserMailer, :invoice_receipt_email).with(invoice)

      expect(invoice.reload.status).to eq("paid")
    end

    it "emails a receipt on every successful charge, not just the first" do
      expect { charge }.to have_enqueued_mail(UserMailer, :invoice_receipt_email).once

      second = create(:invoice, operator: operator, location: location, billable: user, amount_due: 4000, status: "open")
      expect {
        described_class.call(invoice: second, operator: operator)
      }.to have_enqueued_mail(UserMailer, :invoice_receipt_email).with(second)
    end

    it "skips the receipt when the customer has no email" do
      user.update_columns(email: "")

      expect { expect(charge).to be_success }.not_to have_enqueued_mail(UserMailer, :invoice_receipt_email)
      expect(invoice.reload.status).to eq("paid")
    end

    it "skips the receipt for a zero-amount invoice" do
      invoice.update_columns(amount_due: 0)

      expect { expect(charge).to be_success }.not_to have_enqueued_mail(UserMailer, :invoice_receipt_email)
    end

    it "does not fail the charge when the mailer raises" do
      allow(UserMailer).to receive(:invoice_receipt_email).and_raise(StandardError, "boom")

      expect(charge).to be_success
      expect(invoice.reload.status).to eq("paid")
    end
  end

  context "when the charge fails" do
    before { allow_any_instance_of(Location).to receive(:charge_invoice).and_return(false) }

    it "fails, leaves the invoice open, and sends nothing" do
      expect { expect(charge).to be_failure }.not_to have_enqueued_mail(UserMailer, :invoice_receipt_email)
      expect(invoice.reload.status).to eq("open")
    end
  end
end
