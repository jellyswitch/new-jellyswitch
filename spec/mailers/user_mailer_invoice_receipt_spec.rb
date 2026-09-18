require "rails_helper"

RSpec.describe UserMailer, type: :mailer do
  describe "#invoice_receipt_email" do
    let(:operator) { create(:operator, name: "Cowork Tahoe") }
    let(:location) { create(:location, operator: operator) }
    let(:user) { create(:user, operator: operator, name: "Michaela Payne", email: "michaela@example.com") }
    let(:invoice) do
      create(:invoice, operator: operator, location: location, billable: user,
             amount_due: 4000, amount_paid: 4000, status: "paid",
             description: "Cowork Tahoe Day Pass for Friday, September 18")
    end

    it "sends an automatic purchase receipt by default" do
      mail = described_class.invoice_receipt_email(invoice)

      expect(mail.to).to eq(["michaela@example.com"])
      expect(mail.subject).to eq("Your receipt from Cowork Tahoe — $40.00")
      expect(mail.body.encoded).to include("Thanks for your purchase!")
      expect(mail.body.encoded).not_to include("You requested a copy")
      expect(mail.body.encoded).to include("Cowork Tahoe Day Pass for Friday, September 18")
      expect(mail.body.encoded).to include("$40.00")
    end

    it "uses the on-request wording when an admin resends it" do
      mail = described_class.invoice_receipt_email(invoice, requested: true)

      expect(mail.body.encoded).to include("You requested a copy of your receipt")
      expect(mail.body.encoded).not_to include("Thanks for your purchase!")
    end
  end
end
