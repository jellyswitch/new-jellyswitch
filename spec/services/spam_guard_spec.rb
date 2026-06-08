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

    context "with cool-down (marketing sends only)" do
      def marketing_product_send(created, op: operator)
        ProductEmailSend.create!(operator: op, user: user, sendable: user,
                                 email_type: "follow_up", status: "sent",
                                 sent_at: created, created_at: created, updated_at: created)
      end

      it "returns false if user got a marketing email from sender within cool_down_days" do
        marketing_product_send(5.days.ago)
        expect(SpamGuard.eligible?(user, sender: operator, cool_down_days: 30)).to be false
      end

      it "returns true if the marketing email is older than the cool-down window" do
        marketing_product_send(45.days.ago)
        expect(SpamGuard.eligible?(user, sender: operator, cool_down_days: 30)).to be true
      end

      it "ignores marketing emails from a different operator" do
        marketing_product_send(5.days.ago, op: other_operator)
        expect(SpamGuard.eligible?(user, sender: operator, cool_down_days: 30)).to be true
      end

      it "honors cool_down_days: 0 as 'no cool-down'" do
        marketing_product_send(1.day.ago)
        expect(SpamGuard.eligible?(user, sender: operator, cool_down_days: 0)).to be true
      end

      it "counts a recent campaign send as marketing contact (even a one-off)" do
        campaign = Campaign.create!(operator: operator, name: "Promo",
                                    campaign_type: "single", status: "active", segment: {})
        step = CampaignStep.create!(campaign: campaign, position: 0, subject: "Hi", body: "Body")
        CampaignSend.create!(campaign: campaign, campaign_step: step, user: user,
                             status: "sent", sent_at: 3.days.ago, created_at: 3.days.ago)
        expect(SpamGuard.eligible?(user, sender: operator, cool_down_days: 30)).to be false
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

      # These assert the active-series invariant directly. (eligible? would still
      # be false because the recent campaign send trips the marketing cool-down —
      # correct anti-fatigue behavior — so we check in_active_drip? in isolation.)
      it "is not an active-drip enrollment when the campaign is paused / completed" do
        campaign.update!(status: "completed")
        CampaignSend.create!(campaign: campaign, campaign_step: campaign_step,
                             user: user, status: "sent", sent_at: 5.days.ago)
        expect(SpamGuard.in_active_drip?(user, operator)).to be false
      end

      it "is not an active-drip enrollment when the campaign is type single (not drip)" do
        campaign.update!(campaign_type: "single")
        CampaignSend.create!(campaign: campaign, campaign_step: campaign_step,
                             user: user, status: "sent", sent_at: 5.days.ago)
        expect(SpamGuard.in_active_drip?(user, operator)).to be false
      end
    end
  end

  describe "transactional mail does not trip the cool-down" do
    # The whole point of the marketing-only cool-down: an operationally-required
    # email (account confirmation, receipt, password reset) must never suppress a
    # drip/nudge. A confirmation email goes out to EVERY new signup, so counting
    # it would silently kill the signup nudge the cool-down was meant to start.
    it "ignores a transactional email_sent Activity (e.g. signup confirmation)" do
      Activity.create!(user: user, operator: operator, kind: "email_sent",
                       occurred_at: 1.minute.ago, subject: user,
                       payload: { "transactional" => true })
      expect(SpamGuard.eligible?(user, sender: operator, cool_down_days: 30)).to be true
    end

    it "ignores a transactional onboarding product email" do
      ProductEmailSend.create!(operator: operator, user: user, sendable: user,
                               email_type: "onboarding", status: "sent",
                               sent_at: 1.day.ago, created_at: 1.day.ago, updated_at: 1.day.ago)
      expect(SpamGuard.eligible?(user, sender: operator, cool_down_days: 30)).to be true
    end

    it "still blocks when the recent email WAS marketing (regression guard)" do
      ProductEmailSend.create!(operator: operator, user: user, sendable: user,
                               email_type: "nudge", status: "sent",
                               sent_at: 1.day.ago, created_at: 1.day.ago, updated_at: 1.day.ago)
      expect(SpamGuard.eligible?(user, sender: operator, cool_down_days: 30)).to be false
    end
  end
end
