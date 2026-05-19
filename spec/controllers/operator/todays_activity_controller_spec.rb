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
end
