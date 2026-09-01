require "rails_helper"

# Non-payment cutoff (PaymentCutoff): User#payment_suspended? is DERIVED —
# open invoice + recorded suspension notice — and closes the building and
# self-serve booking to the member until the invoice is paid.
RSpec.describe "Payment suspension" do
  let(:location) do
    create(:location, time_zone: "Pacific Time (US & Canada)",
                      working_day_start: "09:00", working_day_end: "18:00")
  end
  let(:operator) { location.operator }
  let(:user) { create(:user, operator: operator, current_location: location, original_location: location) }
  let!(:invoice) do
    create(:invoice, operator: operator, location: location, billable: user,
                     amount_due: 30000, status: "open", due_date: nil,
                     stripe_invoice_id: "in_SUSPEND")
  end

  def suspend!(target = invoice)
    ProductEmailSend.create!(operator: operator, user: user, sendable: target,
                             email_type: PaymentCutoff::SUSPENSION_NOTICE,
                             status: "sent", sent_at: Time.current)
  end

  def membership!
    plan = create(:plan, operator: operator, location: location,
                         building_access_level: :all_hours,
                         always_allow_building_access: true)
    create(:subscription, subscribable: user, billable: user, plan: plan, active: true, paused: false)
    user.reload
  end

  # Bare harness to exercise the private unlock authorization in isolation
  # (same pattern as building_access_level_spec).
  let(:unlock_gate) do
    Class.new do
      include Api::V1::DoorUnlocking
      def can?(u, l) = send(:user_can_access_building?, u, l)
      def denial(u, l) = send(:building_access_denial_message, u, l)
    end.new
  end

  describe "User#payment_suspended?" do
    it "is false with only an open invoice (no suspension notice yet)" do
      expect(user.payment_suspended?).to be(false)
    end

    it "is true once the suspension notice is recorded for a still-open invoice" do
      suspend!
      expect(user.payment_suspended?).to be(true)
    end

    it "lifts instantly when the invoice is paid — no flag to reset" do
      suspend!
      invoice.update!(status: "paid")
      expect(user.payment_suspended?).to be(false)
    end

    it "never suspends staff" do
      suspend!
      user.update!(admin: true)
      expect(user.payment_suspended?).to be(false)
    end
  end

  describe "door access" do
    it "closes the building to a suspended member despite an all-hours membership" do
      membership!
      expect(unlock_gate.can?(user, location)).to be(true)

      suspend!
      expect(unlock_gate.can?(user, location)).to be(false)
    end

    it "reopens the moment the invoice is paid" do
      membership!
      suspend!
      invoice.update!(status: "paid")
      expect(unlock_gate.can?(user, location)).to be(true)
    end

    it "hides the keys list too (lockstep with the unlock gate, PR #668 invariant)" do
      membership!
      expect(user.has_building_access?(location)).to be(true)

      suspend!
      expect(user.reload.has_building_access?(location)).to be(false)
    end

    it "tells the member why in the denial message" do
      suspend!
      expect(unlock_gate.denial(user, location)).to include("past-due balance")
    end

    it "keeps the pending-approval message first for unapproved members" do
      user.update!(approved: false)
      expect(unlock_gate.denial(user, location)).to include("pending approval")
    end
  end

  describe "Billing::Reservations::EnforcePaymentStanding" do
    it "blocks a suspended member when the caller enforces standing" do
      suspend!
      result = Billing::Reservations::EnforcePaymentStanding.call(
        user: user, enforce_payment_standing: true)
      expect(result).to be_failure
      expect(result.message).to include("past-due balance")
    end

    it "no-ops for a member in good standing" do
      result = Billing::Reservations::EnforcePaymentStanding.call(
        user: user, enforce_payment_standing: true)
      expect(result).to be_success
    end

    it "no-ops when the flag is not set (admin / on-behalf flows)" do
      suspend!
      result = Billing::Reservations::EnforcePaymentStanding.call(user: user)
      expect(result).to be_success
    end
  end
end
