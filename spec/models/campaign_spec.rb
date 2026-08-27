# == Schema Information
#
# Table name: campaigns
#
#  id               :bigint(8)        not null, primary key
#  campaign_type    :string           default("single"), not null
#  cool_down_days   :integer          default(30), not null
#  name             :string           not null
#  recipient_count  :integer          default(0)
#  scheduled_at     :datetime
#  segment          :jsonb            not null
#  sent_at          :datetime
#  status           :string           default("draft"), not null
#  suppression_days :integer          default(7)
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  location_id      :bigint(8)
#  operator_id      :bigint(8)        not null
#
# Indexes
#
#  index_campaigns_on_location_id  (location_id)
#  index_campaigns_on_operator_id  (operator_id)
#
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
      # A recent *marketing* send (product nudge) trips the cool-down without
      # being an active-series enrollment.
      ProductEmailSend.create!(operator: operator, user: u, sendable: u,
                               email_type: "nudge", status: "sent",
                               sent_at: 5.days.ago, created_at: 5.days.ago, updated_at: 5.days.ago)
      u
    end

    let!(:recently_emailed_transactional_only) do
      u = create(:user, operator: operator, original_location: location, current_location: location)
      # Only a transactional email (e.g. signup confirmation / receipt). This
      # must NOT exclude them — the cool-down throttles marketing, not all mail.
      Activity.create!(user: u, operator: operator, kind: "email_sent",
                       occurred_at: 5.days.ago, subject: u)
      u
    end

    it "excludes users in another active drip" do
      ids = campaign.build_recipient_query(location).pluck(:id)
      expect(ids).to include(eligible.id)
      expect(ids).not_to include(in_drip.id)
    end

    it "excludes users recently emailed (marketing) by this operator" do
      ids = campaign.build_recipient_query(location).pluck(:id)
      expect(ids).not_to include(recently_emailed.id)
    end

    it "does NOT exclude users whose only recent email was transactional" do
      ids = campaign.build_recipient_query(location).pluck(:id)
      expect(ids).to include(recently_emailed_transactional_only.id)
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

  describe "status predicates" do
    it "reflects the status string" do
      expect(Campaign.new(status: "paused").paused?).to be true
      expect(Campaign.new(status: "completed").completed?).to be true
      expect(Campaign.new(status: "cancelled").cancelled?).to be true
      expect(Campaign.new(status: "draft").paused?).to be false
    end
  end

  describe "#build_recipient_query widget-lead segments (tour_request / concierge_chat)" do
    def sendable_user
      create(:user, operator: operator, original_location: location, current_location: location,
                    email_opted_out: false, email_bounced: false, marketing_suppressed: false)
    end

    let!(:tour_lead) do
      u = sendable_user
      Activity.create!(user: u, operator: operator, kind: "tour_request",
                       occurred_at: 2.days.ago, subject: location, payload: {})
      u
    end
    let!(:chat_lead) do
      u = sendable_user
      Activity.create!(user: u, operator: operator, kind: "chat",
                       occurred_at: 3.days.ago, payload: {})
      u
    end
    let!(:customer_only) { sendable_user }

    def recipient_ids(segment)
      campaign.update!(segment: segment)
      campaign.build_recipient_query(location, apply_spam_guard: false).pluck(:id)
    end

    it "tour_request targets people with a tour_request activity" do
      ids = recipient_ids("customer_types" => %w[tour_request])
      expect(ids).to include(tour_lead.id)
      expect(ids).not_to include(chat_lead.id, customer_only.id)
    end

    it "concierge_chat targets people with a chat activity" do
      ids = recipient_ids("customer_types" => %w[concierge_chat])
      expect(ids).to include(chat_lead.id)
      expect(ids).not_to include(tour_lead.id, customer_only.id)
    end

    it "respects the segment date range via occurred_at" do
      old_lead = sendable_user
      Activity.create!(user: old_lead, operator: operator, kind: "tour_request",
                       occurred_at: 90.days.ago, payload: {})

      ids = recipient_ids(
        "customer_types" => %w[tour_request],
        "date_range" => { "from" => 30.days.ago.to_date.to_s, "to" => Date.current.to_s },
      )
      expect(ids).to include(tour_lead.id)
      expect(ids).not_to include(old_lead.id)
    end
  end

  describe "#build_recipient_query interest targeting (ADR 0022)" do
    def sendable_user
      create(:user, operator: operator, original_location: location, current_location: location,
                    email_opted_out: false, email_bounced: false, marketing_suppressed: false)
    end

    let!(:office_only) do
      u = sendable_user
      InterestTag.record(user: u, product: "office", source: "concierge")
      u
    end
    let!(:membership_only) do
      u = sendable_user
      InterestTag.record(user: u, product: "membership", source: "concierge")
      u
    end
    let!(:both) do
      u = sendable_user
      InterestTag.record(user: u, product: "office", source: "concierge")
      InterestTag.record(user: u, product: "membership", source: "staff")
      u
    end
    let!(:no_interest) { sendable_user }

    def recipient_ids(segment)
      campaign.update!(segment: segment)
      campaign.build_recipient_query(location, apply_spam_guard: false).pluck(:id)
    end

    it "ANY match returns users holding any of the products (union)" do
      ids = recipient_ids("interest_products" => %w[office membership], "interest_match" => "any")
      expect(ids).to include(office_only.id, membership_only.id, both.id)
      expect(ids).not_to include(no_interest.id)
    end

    it "ANY match with a single product" do
      ids = recipient_ids("interest_products" => %w[office], "interest_match" => "any")
      expect(ids).to include(office_only.id, both.id)
      expect(ids).not_to include(membership_only.id, no_interest.id)
    end

    it "ALL match requires every product" do
      ids = recipient_ids("interest_products" => %w[office membership], "interest_match" => "all")
      expect(ids).to contain_exactly(both.id)
    end

    it "no interest filter leaves the audience unfiltered by interest" do
      ids = recipient_ids({})
      expect(ids).to include(office_only.id, membership_only.id, both.id, no_interest.id)
    end

    it "ignores unknown products (can't widen the query)" do
      ids = recipient_ids("interest_products" => %w[parking], "interest_match" => "any")
      expect(ids).to include(no_interest.id, office_only.id) # no interest filter applied
    end

    it "still drops suppressed people even when interested" do
      suppressed = sendable_user
      InterestTag.record(user: suppressed, product: "office", source: "concierge")
      suppressed.update!(marketing_suppressed: true)
      ids = recipient_ids("interest_products" => %w[office], "interest_match" => "any")
      expect(ids).not_to include(suppressed.id)
      expect(ids).to include(office_only.id)
    end

    it "recipient_count_for stays an integer with an ALL (grouped) interest filter" do
      campaign.update!(segment: { "interest_products" => %w[office membership], "interest_match" => "all" })
      expect(campaign.recipient_count_for(location)).to eq(1)
    end
  end
end
