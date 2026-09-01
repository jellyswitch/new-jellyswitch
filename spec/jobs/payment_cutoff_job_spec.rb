require "rails_helper"

# Steps 2 and 3 of the non-payment drip (PaymentCutoff): failure notice →
# warning after 48h → suspension notice after another 48h, each recorded once
# per invoice, and only while the invoice is still open. The suspension row is
# the cutoff — User#payment_suspended? keys off it.
RSpec.describe PaymentCutoffJob, type: :job do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }
  let(:member) { create(:user, operator: operator, current_location: location, original_location: location) }
  let!(:invoice) do
    create(:invoice, operator: operator, location: location, billable: member,
                     amount_due: 30000, status: "open", due_date: nil,
                     stripe_invoice_id: "in_CUTOFF")
  end

  def record(email_type, sent_at:, user: member, sendable: invoice)
    ProductEmailSend.create!(operator: operator, user: user, sendable: sendable,
                             email_type: email_type, status: "sent", sent_at: sent_at)
  end

  describe "warning (step 2)" do
    it "sends the 48h warning once the failure notice is 48h old" do
      record(PaymentCutoff::FAILED_NOTICE, sent_at: 49.hours.ago)

      expect {
        described_class.new.perform
      }.to change { ActionMailer::Base.deliveries.count }.by(1)
      expect(ActionMailer::Base.deliveries.last.subject).to include("paused in 48 hours")
      expect(ProductEmailSend.already_sent?(invoice, PaymentCutoff::WARNING_NOTICE)).to be(true)
      # Not suspended yet — the warning gives 48h to fix it.
      expect(member.reload.payment_suspended?).to be(false)
    end

    it "waits while the failure notice is younger than 48h" do
      record(PaymentCutoff::FAILED_NOTICE, sent_at: 12.hours.ago)

      expect {
        described_class.new.perform
      }.not_to change { ActionMailer::Base.deliveries.count }
    end

    it "does not double-send on a second run" do
      record(PaymentCutoff::FAILED_NOTICE, sent_at: 49.hours.ago)
      described_class.new.perform

      expect {
        described_class.new.perform
      }.not_to change { ActionMailer::Base.deliveries.count }
    end

    it "drops out silently when the invoice got paid" do
      record(PaymentCutoff::FAILED_NOTICE, sent_at: 49.hours.ago)
      invoice.update!(status: "paid")

      expect {
        described_class.new.perform
      }.not_to change { ActionMailer::Base.deliveries.count }
    end
  end

  describe "suspension (step 3)" do
    before do
      record(PaymentCutoff::FAILED_NOTICE, sent_at: 100.hours.ago)
      record(PaymentCutoff::WARNING_NOTICE, sent_at: 49.hours.ago)
    end

    it "sends the suspension notice 48h after the warning and suspends access" do
      expect {
        described_class.new.perform
      }.to change { ActionMailer::Base.deliveries.count }.by(1)
      expect(ActionMailer::Base.deliveries.last.subject).to include("access is paused")
      expect(member.reload.payment_suspended?).to be(true)
    end

    it "suspension lifts itself the moment the invoice is paid" do
      described_class.new.perform
      expect(member.reload.payment_suspended?).to be(true)

      invoice.update!(status: "paid")
      expect(member.reload.payment_suspended?).to be(false)
    end

    it "waits while the warning is younger than 48h" do
      ProductEmailSend.where(email_type: PaymentCutoff::WARNING_NOTICE).update_all(sent_at: 12.hours.ago)

      expect {
        described_class.new.perform
      }.not_to change { ActionMailer::Base.deliveries.count }
      expect(member.reload.payment_suspended?).to be(false)
    end
  end

  describe "exclusions (individuals only, v1)" do
    it "never advances an org-billed invoice" do
      org = create(:organization, operator: operator)
      org_invoice = create(:invoice, operator: operator, location: location, billable: org,
                           amount_due: 50000, status: "open", due_date: nil,
                           stripe_invoice_id: "in_ORG")
      record(PaymentCutoff::FAILED_NOTICE, sent_at: 49.hours.ago, user: org.owner || member, sendable: org_invoice)
      invoice.update!(status: "paid") # keep the individual invoice out of the way

      expect {
        described_class.new.perform
      }.not_to change { ActionMailer::Base.deliveries.count }
    end

    it "never advances an out-of-band (net-30) member" do
      member.update!(out_of_band: true)
      record(PaymentCutoff::FAILED_NOTICE, sent_at: 49.hours.ago)

      expect {
        described_class.new.perform
      }.not_to change { ActionMailer::Base.deliveries.count }
    end

    it "never advances an invoice whose due_date is still in the future" do
      invoice.update!(due_date: 10.days.from_now)
      record(PaymentCutoff::FAILED_NOTICE, sent_at: 49.hours.ago)

      expect {
        described_class.new.perform
      }.not_to change { ActionMailer::Base.deliveries.count }
    end

    it "never advances staff" do
      member.update!(admin: true)
      record(PaymentCutoff::FAILED_NOTICE, sent_at: 49.hours.ago)

      expect {
        described_class.new.perform
      }.not_to change { ActionMailer::Base.deliveries.count }
    end
  end
end
