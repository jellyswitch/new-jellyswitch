require "rails_helper"

RSpec.describe SpamGuard do
  let(:operator) { create(:operator) }
  let(:other_operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }
  let(:user) { create(:user, operator: operator, current_location: location) }

  describe ".eligible?" do
    it "returns true for a fresh user with no enrollments and no recent emails" do
      expect(SpamGuard.eligible?(user, sender: operator, cool_down_days: 30)).to be true
    end

    it "returns true when user or sender is nil (defensive)" do
      expect(SpamGuard.eligible?(nil, sender: operator, cool_down_days: 30)).to be true
      expect(SpamGuard.eligible?(user, sender: nil, cool_down_days: 30)).to be true
    end

    context "with cool-down" do
      it "returns false if user received an email from sender within cool_down_days" do
        Activity.create!(user: user, operator: operator, kind: "email_sent",
                         occurred_at: 5.days.ago, subject: user)
        expect(SpamGuard.eligible?(user, sender: operator, cool_down_days: 30)).to be false
      end

      it "returns true if user received an email from sender before the cool-down window" do
        Activity.create!(user: user, operator: operator, kind: "email_sent",
                         occurred_at: 45.days.ago, subject: user)
        expect(SpamGuard.eligible?(user, sender: operator, cool_down_days: 30)).to be true
      end

      it "ignores emails from a different operator" do
        Activity.create!(user: user, operator: other_operator, kind: "email_sent",
                         occurred_at: 5.days.ago, subject: user)
        expect(SpamGuard.eligible?(user, sender: operator, cool_down_days: 30)).to be true
      end

      it "honors cool_down_days: 0 as 'no cool-down'" do
        Activity.create!(user: user, operator: operator, kind: "email_sent",
                         occurred_at: 1.day.ago, subject: user)
        expect(SpamGuard.eligible?(user, sender: operator, cool_down_days: 0)).to be true
      end
    end

    context "with welcome-drip enrollment" do
      it "returns false if user is currently enrolled in the welcome drip" do
        user.enroll_in_welcome_drip!
        expect(SpamGuard.eligible?(user, sender: operator, cool_down_days: 30)).to be false
      end

      it "returns true if the welcome-drip enrollment is older than ACTIVE_SERIES_LOOKBACK" do
        ProductEmailSend.create!(operator: operator, user: user, sendable: user,
                                 email_type: User::WELCOME_DRIP_ENROLLED_KEY,
                                 status: "scheduled", sent_at: 90.days.ago,
                                 created_at: 90.days.ago, updated_at: 90.days.ago)
        expect(SpamGuard.eligible?(user, sender: operator, cool_down_days: 30)).to be true
      end
    end

    context "with active drip campaign" do
      let(:campaign) do
        Campaign.create!(operator: operator, name: "Spring drip",
                         campaign_type: "drip", status: "active", segment: {})
      end
      let(:campaign_step) do
        CampaignStep.create!(campaign: campaign, position: 0, subject: "Hello", body: "Body")
      end

      it "returns false if user is in a sent step of an active drip" do
        CampaignSend.create!(campaign: campaign, campaign_step: campaign_step,
                             user: user, status: "sent", sent_at: 5.days.ago)
        expect(SpamGuard.eligible?(user, sender: operator, cool_down_days: 30)).to be false
      end

      it "returns true if the campaign is paused / completed (not active)" do
        campaign.update!(status: "completed")
        CampaignSend.create!(campaign: campaign, campaign_step: campaign_step,
                             user: user, status: "sent", sent_at: 5.days.ago)
        expect(SpamGuard.eligible?(user, sender: operator, cool_down_days: 30)).to be true
      end

      it "returns true if the campaign is type single (not drip)" do
        campaign.update!(campaign_type: "single")
        CampaignSend.create!(campaign: campaign, campaign_step: campaign_step,
                             user: user, status: "sent", sent_at: 5.days.ago)
        expect(SpamGuard.eligible?(user, sender: operator, cool_down_days: 30)).to be true
      end
    end
  end

  describe "transactional bypass" do
    it "is not consulted when a transactional mailer fires (caller responsibility)" do
      # Transactional emails (password resets, booking confirms) DO log :email_sent
      # Activities — so they affect the cool-down check at the next eligibility
      # call. But SpamGuard itself isn't part of their send path. This is the
      # invariant: SpamGuard only blocks when callers consult it.
      Activity.create!(user: user, operator: operator, kind: "email_sent",
                       occurred_at: 1.minute.ago, subject: user,
                       payload: { "transactional" => true })
      # The transactional mailer itself didn't call SpamGuard — it just sent.
      # But a subsequent marketing send WOULD be blocked by the cool-down.
      expect(SpamGuard.eligible?(user, sender: operator, cool_down_days: 30)).to be false
    end
  end
end
