require "rails_helper"

# Regression: a bundle-sourced entry pass (minted by burning a prepaid N-Pack
# on building entry) carries the full pack price in day_pass_type.amount_in_cents.
# It must appear as a visit in the day-passes list but with $0 cost, and must be
# excluded from the day's revenue total — otherwise each daily entry double-counts
# the one-time pack purchase as recurring day-pass revenue.
RSpec.describe Api::V1::Admin::TodaysActivityController, type: :controller do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator, name: "Zephyr Cove", day_pass_period_start: "04:00") }
  # superadmin so enforce_location_scope! lets the request through to any location
  let(:admin)    { create(:user, operator: operator, role: "superadmin", name: "Adam Admin") }

  let(:single_type) { create(:day_pass_type, operator: operator, location: location, name: "Single", amount_in_cents: 2_500) }
  let(:pack_type)   { create(:day_pass_type, operator: operator, location: location, name: "10-Pack", amount_in_cents: 20_000) }

  let(:individual) { create(:user, operator: operator, name: "Individual Ida") }
  let(:bundler)    { create(:user, operator: operator, name: "Bundle Bob") }

  before do
    allow(controller).to receive(:authenticate_api_v1).and_return(true)
    allow(controller).to receive(:current_api_user).and_return(admin)
    allow(controller).to receive(:current_tenant).and_return(operator)
    allow(controller).to receive(:current_location).and_return(location)

    # A normally-purchased day pass for today → $25 of real revenue.
    create(:day_pass, user: individual, billable: individual, operator: operator,
                      location: location, day_pass_type: single_type, day: Date.current)

    # A 10-Pack bundle burned on entry today → mints a $200-type DayPass.
    DayPassBundle.create!(user: bundler, billable: bundler, operator: operator, location: location,
                          day_pass_type: pack_type, quantity_purchased: 10, passes_remaining: 10, purchased_at: Time.current)
    Billing::DayPassBundles::ConsumeOnEntry.call(user: bundler, location: location)
  end

  describe "GET #index" do
    subject(:body) { get :index; JSON.parse(response.body) }

    it "lists the bundle entry as a visit with $0 cost, and the individual pass at its real price" do
      rows = body["day_passes"].index_by { |r| r["user_id"] }
      expect(rows[individual.id]["cost"]).to eq(2_500)
      expect(rows[bundler.id]["cost"]).to eq(0)
    end

    it "counts only the individual pass in the revenue total, not the pack price" do
      # $25 individual pass only — the $200 pack is not recurring revenue.
      expect(body["revenue"]).to eq(2_500)
    end
  end
end
