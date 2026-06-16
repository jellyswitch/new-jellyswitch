require "rails_helper"

RSpec.describe "API v1 day pass bundles", type: :request do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }
  let(:user) { create(:user, operator: operator) }
  let(:type) do
    create(:day_pass_type, operator: operator, location: location,
           quantity: 5, amount_in_cents: 10_000, available: true, visible: true)
  end

  def auth_headers_for(u)
    payload = { user_id: u.id, operator_id: u.operator_id, exp: 1.hour.from_now.to_i }
    token = JWT.encode(payload, Rails.application.secret_key_base, "HS256")
    {
      "Authorization" => "Bearer #{token}",
      "X-Operator-Subdomain" => u.operator.subdomain,
    }
  end

  def create_bundle(**attrs)
    defaults = {
      user: user,
      billable: user,
      operator: operator,
      location: location,
      day_pass_type: type,
      quantity_purchased: 5,
      purchased_at: Time.current,
    }
    DayPassBundle.create!(defaults.merge(attrs))
  end

  # ── GET /api/v1/day_pass_bundles ──────────────────────────────────────────

  describe "GET /api/v1/day_pass_bundles" do
    it "lists the current user's active bundles" do
      active = create_bundle(passes_remaining: 4)
      create_bundle(passes_remaining: 0)           # excluded (empty)
      create_bundle(passes_remaining: 3, expires_at: 1.day.ago)  # excluded (expired)

      get "/api/v1/day_pass_bundles", headers: auth_headers_for(user)

      expect(response).to have_http_status(:ok)
      ids = JSON.parse(response.body).map { |b| b["id"] }
      expect(ids).to eq([active.id])
      expect(JSON.parse(response.body).first).to include("passes_remaining" => 4)
    end
  end

  # ── POST /api/v1/day_pass_bundles/:id/check_in_guest ─────────────────────

  describe "POST /api/v1/day_pass_bundles/:id/check_in_guest" do
    it "checks in a guest, burning one pass" do
      b = create_bundle(passes_remaining: 3)

      post "/api/v1/day_pass_bundles/#{b.id}/check_in_guest",
           params: { guest_name: "Sam" },
           headers: auth_headers_for(user)

      expect(response).to have_http_status(:ok).or have_http_status(:created)
      expect(b.reload.passes_remaining).to eq(2)
      expect(b.redemptions.last.kind).to eq("guest")
    end

    it "404s for someone else's bundle" do
      other = create(:user, operator: operator)
      b = DayPassBundle.create!(
        user: other, billable: other, operator: operator, location: location,
        day_pass_type: type, quantity_purchased: 5, passes_remaining: 5,
        purchased_at: Time.current
      )

      post "/api/v1/day_pass_bundles/#{b.id}/check_in_guest",
           params: { guest_name: "X" },
           headers: auth_headers_for(user)

      expect(response).to have_http_status(:not_found)
    end

    it "422s when the bundle is empty" do
      b = create_bundle(passes_remaining: 0)  # owned but not active

      post "/api/v1/day_pass_bundles/#{b.id}/check_in_guest",
           params: { guest_name: "X" },
           headers: auth_headers_for(user)

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
