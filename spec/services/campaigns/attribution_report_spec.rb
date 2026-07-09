require "rails_helper"

RSpec.describe Campaigns::AttributionReport do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }
  let(:campaign) { Campaign.create!(operator: operator, location: location, name: "Winter", campaign_type: "single", status: "active", segment: {}) }
  let(:step) { CampaignStep.create!(campaign: campaign, position: 0, subject: "Hi", body: "x") }

  def person(name = nil)
    attrs = { operator: operator, original_location: location }
    attrs[:name] = name if name
    create(:user, **attrs)
  end

  def opened_send(user, opened_at:, clicked: false)
    CampaignSend.create!(campaign: campaign, campaign_step: step, user: user, status: "sent",
                         sent_at: opened_at - 1.hour, opened: true, opened_at: opened_at,
                         clicked: clicked, clicked_at: (clicked ? opened_at : nil))
  end

  def conversion(user, kind:, at:)
    Activity.create!(user: user, operator: operator, kind: kind, occurred_at: at, subject: user)
  end

  def payment(user, cents:, at:)
    Activity.create!(user: user, operator: operator, kind: "payment_succeeded", occurred_at: at,
                     subject: user, payload: { "amount_paid" => cents })
  end

  describe "#scorecard" do
    it "reports sent/opened/clicked, windowed conversions, and revenue" do
      base = 10.days.ago

      converter = person("Converter")
      opened_send(converter, opened_at: base, clicked: true)
      conversion(converter, kind: "day_pass", at: base + 2.days)
      payment(converter, cents: 5000, at: base + 2.days)

      late = person("Late") # opened, but converted 20 days later — outside the 14-day window
      opened_send(late, opened_at: base)
      conversion(late, kind: "subscription_started", at: base + 20.days)

      opened_send(person("Silent"), opened_at: base) # opened, never converted

      # sent but never opened
      CampaignSend.create!(campaign: campaign, campaign_step: step, user: person("Unopened"),
                           status: "sent", sent_at: base)

      s = described_class.new(campaign).scorecard
      expect(s[:sent]).to eq(4)
      expect(s[:opened]).to eq(3)
      expect(s[:clicked]).to eq(1)
      expect(s[:converted]).to eq(1)       # only the in-window converter
      expect(s[:revenue_cents]).to eq(5000)
    end

    it "counts an office_lease as a money-bearing conversion" do
      base = 5.days.ago
      u = person
      opened_send(u, opened_at: base)
      conversion(u, kind: "office_lease", at: base + 1.day)
      expect(described_class.new(campaign).scorecard[:converted]).to eq(1)
    end

    it "does not credit a conversion that happened BEFORE the open" do
      base = 5.days.ago
      u = person
      conversion(u, kind: "day_pass", at: base - 2.days) # bought before opening
      opened_send(u, opened_at: base)
      expect(described_class.new(campaign).scorecard[:converted]).to eq(0)
    end

    it "does NOT credit revenue for an opener who paid routine dues but never converted" do
      base = 6.days.ago
      u = person
      opened_send(u, opened_at: base)
      payment(u, cents: 19_900, at: base + 3.days) # recurring membership dues, no conversion

      s = described_class.new(campaign).scorecard
      expect(s[:converted]).to eq(0)
      expect(s[:revenue_cents]).to eq(0)
    end

    it "counts a drip conversion anchored on a LATER step's open (not just the first)" do
      step2 = CampaignStep.create!(campaign: campaign, position: 1, subject: "Step 2", body: "y")
      u = person
      CampaignSend.create!(campaign: campaign, campaign_step: step, user: u, status: "sent",
                           sent_at: 40.days.ago, opened: true, opened_at: 40.days.ago)
      CampaignSend.create!(campaign: campaign, campaign_step: step2, user: u, status: "sent",
                           sent_at: 3.days.ago, opened: true, opened_at: 3.days.ago)
      conversion(u, kind: "subscription_started", at: 1.day.ago)

      # earliest open (40d ago) is out of window; the step-2 open (3d ago) is in.
      expect(described_class.new(campaign).scorecard[:converted]).to eq(1)
    end
  end

  describe ".campaign_for_conversion (per-person last-touch)" do
    it "attributes to a campaign opened within the window before the conversion" do
      base = 8.days.ago
      u = person
      opened_send(u, opened_at: base)
      act = conversion(u, kind: "day_pass", at: base + 3.days)
      expect(described_class.campaign_for_conversion(act)).to eq(campaign)
    end

    it "returns nil when the open was outside the window" do
      u = person
      opened_send(u, opened_at: 30.days.ago)
      act = conversion(u, kind: "day_pass", at: Time.current)
      expect(described_class.campaign_for_conversion(act)).to be_nil
    end

    it "returns nil for a non-conversion activity" do
      u = person
      opened_send(u, opened_at: 2.days.ago)
      act = conversion(u, kind: "checkin", at: Time.current)
      expect(described_class.campaign_for_conversion(act)).to be_nil
    end

    it "resolves from preloaded opened_sends (batched path — no per-row query)" do
      base = 5.days.ago
      u = person
      opened_send(u, opened_at: base)
      act = conversion(u, kind: "day_pass", at: base + 1.day)
      preloaded = CampaignSend.where(user_id: u.id, opened: true).includes(:campaign).order(opened_at: :desc).to_a

      expect(described_class.campaign_for_conversion(act, opened_sends: preloaded)).to eq(campaign)
    end
  end
end
