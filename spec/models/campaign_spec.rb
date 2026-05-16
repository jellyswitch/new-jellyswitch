require "rails_helper"

RSpec.describe Campaign, type: :model do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }
  let(:campaign) do
    Campaign.create!(operator: operator, location: location,
                     name: "Spring promo", campaign_type: "single",
                     status: "draft", segment: {}, cool_down_days: 30)
  end

  describe "#build_recipient_query with SpamGuard filter" do
    let!(:eligible) do
      create(:user, operator: operator, original_location: location, current_location: location,
                    email_opted_out: false, email_bounced: false, marketing_suppressed: false)
    end

    let!(:in_drip) do
      u = create(:user, operator: operator, original_location: location, current_location: location)
      drip = Campaign.create!(operator: operator, name: "Drip",
                              campaign_type: "drip", status: "active", segment: {})
      step = CampaignStep.create!(campaign: drip, position: 0, subject: "Hi", body: "x")
      CampaignSend.create!(campaign: drip, campaign_step: step, user: u,
                           status: "sent", sent_at: 5.days.ago)
      u
    end

    let!(:recently_emailed) do
      u = create(:user, operator: operator, original_location: location, current_location: location)
      Activity.create!(user: u, operator: operator, kind: "email_sent",
                       occurred_at: 5.days.ago, subject: u)
      u
    end

    it "excludes users in another active drip" do
      ids = campaign.build_recipient_query(location).pluck(:id)
      expect(ids).to include(eligible.id)
      expect(ids).not_to include(in_drip.id)
    end

    it "excludes users recently emailed by this operator" do
      ids = campaign.build_recipient_query(location).pluck(:id)
      expect(ids).not_to include(recently_emailed.id)
    end

    it "the raw query (apply_spam_guard: false) still includes them" do
      ids = campaign.build_recipient_query(location, apply_spam_guard: false).pluck(:id)
      expect(ids).to include(eligible.id, in_drip.id, recently_emailed.id)
    end

    it "spam_guard_excluded_count_for matches the difference" do
      raw = campaign.build_recipient_query(location, apply_spam_guard: false).count
      filtered = campaign.build_recipient_query(location, apply_spam_guard: true).count
      expect(campaign.spam_guard_excluded_count_for(location)).to eq(raw - filtered)
    end

    it "honors a cool_down_days: 0 setting" do
      campaign.update!(cool_down_days: 0)
      ids = campaign.build_recipient_query(location).pluck(:id)
      # recently_emailed user is no longer excluded by cool-down; only the
      # active-drip enrollment still excludes in_drip.
      expect(ids).to include(recently_emailed.id)
      expect(ids).not_to include(in_drip.id)
    end
  end

  describe "100 candidates, 20 in active drip → 80 recipients (Phase 6.2 plan acceptance)" do
    it "filters as expected" do
      drip = Campaign.create!(operator: operator, name: "Active drip",
                              campaign_type: "drip", status: "active", segment: {})
      step = CampaignStep.create!(campaign: drip, position: 0, subject: "X", body: "Y")

      candidates = Array.new(20) do
        create(:user, operator: operator, original_location: location, current_location: location)
      end
      candidates.each do |u|
        CampaignSend.create!(campaign: drip, campaign_step: step, user: u,
                             status: "sent", sent_at: 3.days.ago)
      end
      # 80 more fresh candidates
      80.times do
        create(:user, operator: operator, original_location: location, current_location: location)
      end

      total = campaign.build_recipient_query(location, apply_spam_guard: false).count
      filtered = campaign.build_recipient_query(location, apply_spam_guard: true).count
      expect(total).to eq(100)
      expect(filtered).to eq(80)
      expect(campaign.spam_guard_excluded_count_for(location)).to eq(20)
    end
  end
end
