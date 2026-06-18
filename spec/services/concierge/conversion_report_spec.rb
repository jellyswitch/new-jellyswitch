require "rails_helper"

# The Concierge's headline metric: do Persons who chatted convert (purchase)
# at a higher rate than Persons who didn't? Computed entirely from the Activity
# timeline — no separate analytics pipeline.
RSpec.describe Concierge::ConversionReport do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }

  def member(name)
    create(:user, operator: operator, role: "unassigned", original_location: location, name: name)
  end

  def chat!(user, at: Time.current)
    Activity.create!(operator: operator, user: user, kind: "chat", occurred_at: at,
                     subject: location, payload: { "source" => "concierge" })
  end

  def purchase!(user, at: Time.current, kind: "day_pass")
    Activity.create!(operator: operator, user: user, kind: kind, occurred_at: at)
  end

  subject(:report) { described_class.new(operator: operator).call }

  describe "lifetime cohort lift" do
    before do
      # Chatters: 3 accounts, 2 of them bought.
      c1 = member("Chatter Bought 1"); chat!(c1); purchase!(c1)
      c2 = member("Chatter Bought 2"); chat!(c2); purchase!(c2, kind: "subscription_started")
      c3 = member("Chatter NoBuy");    chat!(c3)
      # Non-chatters: 4 accounts, 1 bought.
      n1 = member("NoChat Bought");    purchase!(n1)
      member("NoChat 1"); member("NoChat 2"); member("NoChat 3")
    end

    it "computes chatter vs non-chatter conversion rates" do
      expect(report[:chatters][:count]).to eq(3)
      expect(report[:chatters][:converted]).to eq(2)
      expect(report[:chatters][:rate]).to be_within(0.001).of(2.0 / 3.0)

      expect(report[:non_chatters][:count]).to eq(4)
      expect(report[:non_chatters][:converted]).to eq(1)
      expect(report[:non_chatters][:rate]).to be_within(0.001).of(0.25)
    end

    it "reports the lift (chatter rate ÷ non-chatter rate)" do
      expect(report[:lift]).to be_within(0.01).of((2.0 / 3.0) / 0.25) # ≈ 2.67×
    end

    it "excludes staff accounts from both cohorts" do
      create(:user, operator: operator, role: "admin", original_location: location)
      create(:user, operator: operator, role: "general-manager", original_location: location)
      expect(report[:chatters][:count] + report[:non_chatters][:count]).to eq(7)
    end
  end

  describe "windowed chatter conversion (purchase within N days of first chat)" do
    it "counts a purchase inside the window but not one long after" do
      in_window  = member("Quick");  chat!(in_window, at: 20.days.ago);  purchase!(in_window, at: 15.days.ago)  # 5d later
      out_window = member("Slow");    chat!(out_window, at: 60.days.ago); purchase!(out_window, at: 10.days.ago) # ~50d later
      chat_only  = member("NoBuy");   chat!(chat_only, at: 5.days.ago)

      windowed = described_class.new(operator: operator, window_days: 14).call[:chatters_within_window]
      expect(windowed[:count]).to eq(3)
      expect(windowed[:converted]).to eq(1) # only the 5-day buyer
    end
  end

  it "handles an empty operator without dividing by zero" do
    expect(report[:chatters]).to eq({ count: 0, converted: 0, rate: 0.0 })
    expect(report[:lift]).to eq(0.0)
  end
end
