require 'rails_helper'

# Ban vs archive: archive is a soft delete that keeps every member ability;
# ban is a refusal (no purchases, no in-app messaging, off marketing lists)
# with a sticky marker that only lift_ban! clears.
RSpec.describe User, "banning" do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }
  let(:staff)    { create(:user, operator: operator, role: "admin", original_location: location) }
  let(:member)   { create(:user, operator: operator, original_location: location, approved: true) }

  describe "#ban!" do
    it "archives, unapproves, suppresses marketing and records who did it" do
      member.ban!(by: staff)
      member.reload

      expect(member).to be_banned
      expect(member.banned_by).to eq(staff)
      expect(member.archived).to be true
      expect(member.approved).to be false
      expect(member.marketing_suppressed).to be true
      expect(member.marketing_suppressed_reason).to eq(User::BANNED_MARKETING_REASON)
    end
  end

  describe "#lift_ban!" do
    it "restores an approved, visible member and clears the ban's suppression" do
      member.ban!(by: staff)
      member.lift_ban!
      member.reload

      expect(member).not_to be_banned
      expect(member.banned_by).to be_nil
      expect(member.archived).to be false
      expect(member.approved).to be true
      expect(member.marketing_suppressed).to be false
    end

    it "keeps a suppression the member had before the ban" do
      member.update_columns(marketing_suppressed: true, marketing_suppressed_reason: "Unsubscribed")
      member.ban!(by: staff)
      member.lift_ban!
      member.reload

      expect(member.marketing_suppressed).to be true
      expect(member.marketing_suppressed_reason).to eq("Unsubscribed")
    end
  end

  describe "in-app messaging" do
    it "refuses a new thread from a banned member with the ban message" do
      member.ban!(by: staff)
      thread = build(:member_feedback, user: member, operator: operator, location: location)
      expect(thread).not_to be_valid
      expect(thread.errors[:base]).to include(User::BANNED_MESSAGE)
    end
  end

  describe "purchases" do
    let(:plan) { create(:plan, operator: operator, location: location) }

    it "refuses a membership for a banned member before touching billing" do
      member.ban!(by: staff)
      result = Billing::Subscription::SaveSubscription.call(
        subscription: Subscription.new(plan: plan, subscribable: member),
        user: member, location: location, operator: operator, start_day: Date.current,
      )
      expect(result).to be_failure
      expect(result.message).to eq(User::BANNED_MESSAGE)
      expect(member.subscriptions.count).to eq(0)
    end

    it "still lets a merely archived member buy a membership (archive keeps abilities)" do
      member.update_columns(archived: true)
      result = Billing::Subscription::SaveSubscription.call(
        subscription: Subscription.new(plan: plan, subscribable: member),
        user: member, location: location, operator: operator, start_day: Date.current,
      )
      # Fails on the billing-info check, not on the archive — the message proves which gate.
      expect(result.message).not_to eq(User::BANNED_MESSAGE)
    end

    it "refuses a day pass for a banned member" do
      member.ban!(by: staff)
      result = Billing::DayPasses::SaveDayPass.call(
        user_id: member.id, operator: operator, location: location, params: { day_pass_type: 0 },
      )
      expect(result).to be_failure
      expect(result.message).to eq(User::BANNED_MESSAGE)
    end

    it "refuses a bundle for a banned member" do
      member.ban!(by: staff)
      result = Billing::DayPassBundles::SaveBundle.call(
        user_id: member.id, operator: operator, location: location, params: { day_pass_type: 0 },
      )
      expect(result).to be_failure
      expect(result.message).to eq(User::BANNED_MESSAGE)
    end
  end
end
