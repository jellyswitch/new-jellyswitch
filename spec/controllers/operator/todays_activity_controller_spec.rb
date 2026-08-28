require "rails_helper"

# Regression: a sister location's signups must never appear in the
# current location's "Who's Coming Today" view. Bug surfaced 2026-05-19
# when an Untethered Zephyr Cove admin saw a Fulton member listed under
# new members because the underlying query scoped only by operator.
RSpec.describe Operator::TodaysActivityController, type: :controller do
  let(:operator) { create(:operator) }
  let(:zephyr) { create(:location, operator: operator, name: "Zephyr Cove") }
  let(:fulton) { create(:location, operator: operator, name: "Fulton") }
  let(:admin_user) { create(:user, operator: operator, role: "superadmin", original_location: zephyr, current_location: zephyr) }

  let(:zephyr_plan) { create(:plan, operator: operator, location: zephyr, amount_in_cents: 10_000) }
  let(:fulton_plan) { create(:plan, operator: operator, location: fulton, amount_in_cents: 25_000) }

  let!(:zephyr_member) do
    u = create(:user, operator: operator, original_location: zephyr, current_location: zephyr, name: "Zephyr Zoe", approved: true)
    create(:subscription, plan: zephyr_plan, subscribable: u, billable: u, active: true)
    u
  end

  let!(:fulton_member) do
    u = create(:user, operator: operator, original_location: fulton, current_location: fulton, name: "Fulton Fred", approved: true)
    create(:subscription, plan: fulton_plan, subscribable: u, billable: u, active: true)
    u
  end

  before do
    request.host = "#{operator.subdomain}.lvh.me"
    allow(controller).to receive(:current_location).and_return(zephyr)
    allow(controller).to receive(:current_user).and_return(admin_user)
  end

  describe "GET #index" do
    before { get :index }

    it "lists new members from the current location only" do
      names = assigns(:new_members).map(&:name)
      expect(names).to include("Zephyr Zoe")
      expect(names).not_to include("Fulton Fred")
    end

    it "counts only the current location's new subscriptions in revenue" do
      # Zephyr plan is $100, Fulton plan is $250. Only $100 belongs here.
      expect(assigns(:new_subscription_revenue)).to eq(100.0)
    end
  end

  # Regression: a bundle-sourced entry pass (minted by burning a prepaid
  # N-Pack on building entry) carries the full pack price in
  # day_pass_type.amount_in_cents. Summing that per daily entry double-counts
  # the one-time bundle purchase as recurring day-pass revenue. The revenue
  # total must exclude bundle entries while still showing them as visits.
  describe "GET #index day-pass revenue with bundle entries" do
    let(:single_type) { create(:day_pass_type, operator: operator, location: zephyr, name: "Single", amount_in_cents: 2_500) }
    let(:pack_type)   { create(:day_pass_type, operator: operator, location: zephyr, name: "10-Pack", quantity: 10, amount_in_cents: 20_000) }

    let(:individual)  { create(:user, operator: operator, original_location: zephyr, current_location: zephyr, name: "Individual Ida") }
    let(:bundler)     { create(:user, operator: operator, original_location: zephyr, current_location: zephyr, name: "Bundle Bob") }

    before do
      # A normally-purchased day pass for today → $25 of real revenue.
      create(:day_pass, user: individual, billable: individual, operator: operator,
                        location: zephyr, day_pass_type: single_type, day: Date.current)

      # A 10-Pack bundle, burned on entry today → mints a DayPass whose
      # day_pass_type.amount_in_cents is the full $200 pack price.
      DayPassBundle.create!(user: bundler, billable: bundler, operator: operator, location: zephyr,
                            day_pass_type: pack_type, quantity_purchased: 10, passes_remaining: 10, purchased_at: Time.current)
      Billing::DayPassBundles::ConsumeOnEntry.call(user: bundler, location: zephyr)

      get :index
    end

    it "still lists the bundle entry as a visit today" do
      expect(assigns(:day_passes).map(&:user_id)).to include(bundler.id)
    end

    it "excludes the bundle entry's full pack price from day-pass revenue" do
      # Only the $25 individual pass counts — NOT the $200 pack price.
      expect(assigns(:day_pass_revenue)).to eq(25.0)
    end

    it "flags the bundle entry (and not the individual pass) for $0/Bundle display" do
      ids = assigns(:bundle_sourced_day_pass_ids)
      bundle_pass = DayPass.find_by(user: bundler, day: Date.current)
      single_pass = DayPass.find_by(user: individual, day: Date.current)
      expect(ids).to include(bundle_pass.id)
      expect(ids).not_to include(single_pass.id)
    end
  end
end
