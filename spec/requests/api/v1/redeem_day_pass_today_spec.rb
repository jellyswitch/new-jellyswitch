require "rails_helper"

RSpec.describe "POST /api/v1/day_passes/redeem_today", type: :request do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }
  let(:user)     { create(:user, operator: operator, current_location: location) }
  let(:type) do
    create(:day_pass_type, operator: operator, location: location,
           quantity: 5, amount_in_cents: 10_000, available: true, visible: true)
  end

  def auth_headers_for(u)
    payload = { user_id: u.id, operator_id: u.operator_id, exp: 1.hour.from_now.to_i }
    token = JWT.encode(payload, Rails.application.secret_key_base, "HS256")
    {
      "Authorization"        => "Bearer #{token}",
      "X-Operator-Subdomain" => u.operator.subdomain,
    }
  end

  def create_bundle(**attrs)
    defaults = {
      user:               user,
      billable:           user,
      operator:           operator,
      location:           location,
      day_pass_type:      type,
      quantity_purchased: 5,
      purchased_at:       Time.current,
    }
    DayPassBundle.create!(defaults.merge(attrs))
  end

  def post_redeem
    post "/api/v1/day_passes/redeem_today", headers: auth_headers_for(user)
  end

  # ── happy path ─────────────────────────────────────────────────────────────

  context "member has an active bundle and no other coverage today" do
    let!(:bundle) { create_bundle(passes_remaining: 5) }

    it "returns 200 with status=redeemed and the new passes_remaining" do
      post_redeem

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["status"]).to eq("redeemed")
      expect(body["passes_remaining"]).to eq(4)
    end

    it "decrements the bundle by 1" do
      expect { post_redeem }.to change { bundle.reload.passes_remaining }.from(5).to(4)
    end

    it "mints a DayPass for today" do
      expect { post_redeem }.to change {
        DayPass.where(user: user, location: location, day: Date.current).count
      }.by(1)
    end
  end

  # ── idempotency: already covered for the period ────────────────────────────

  context "member posts a second time in the same business-day period" do
    let!(:bundle) { create_bundle(passes_remaining: 5) }

    before { post_redeem }  # first call burns one pass

    it "returns 200 with status=already_active_today" do
      post_redeem   # second call

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["status"]).to eq("already_active_today")
    end

    it "does NOT decrement the bundle a second time" do
      expect { post_redeem }.not_to change { bundle.reload.passes_remaining }
    end

    it "does NOT mint a second DayPass" do
      expect { post_redeem }.not_to change {
        DayPass.where(user: user, location: location, day: Date.current).count
      }
    end
  end

  context "member already has an active subscription (already covered)" do
    let!(:bundle) { create_bundle(passes_remaining: 5) }

    before do
      allow_any_instance_of(User).to receive(:has_active_subscription?).and_return(true)
    end

    it "returns 200 with status=already_active_today (not an error)" do
      post_redeem

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["status"]).to eq("already_active_today")
    end

    it "does NOT burn a pass" do
      expect { post_redeem }.not_to change { bundle.reload.passes_remaining }
    end
  end

  # ── no passes ──────────────────────────────────────────────────────────────

  context "member has no active bundle and no other coverage" do
    it "returns 422 with an error message" do
      post_redeem

      expect(response).to have_http_status(:unprocessable_entity)
      body = JSON.parse(response.body)
      expect(body["error"]).to eq("You don't have any day passes left.")
    end

    it "does NOT create a DayPass" do
      expect { post_redeem }.not_to change(DayPass, :count)
    end
  end

  context "member has an exhausted bundle (passes_remaining=0)" do
    before { create_bundle(passes_remaining: 0) }

    it "returns 422" do
      post_redeem

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  # ── unauthenticated ────────────────────────────────────────────────────────

  it "returns 401 without auth" do
    post "/api/v1/day_passes/redeem_today"
    expect(response).to have_http_status(:unauthorized)
  end
end
