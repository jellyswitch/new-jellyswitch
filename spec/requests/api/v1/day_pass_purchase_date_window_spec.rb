require "rails_helper"

# Regression: the web form's year dropdown let a member buy a pass for today's
# date NEXT year ($40, day 2027-07-17, invisible in every "today" view). The
# API accepted any parseable date. Self-serve purchases and reschedules are now
# bounded to today..today+DayPass::MAX_ADVANCE_DAYS.
RSpec.describe "API v1 day pass purchase date window", type: :request do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }
  let(:user) do
    create(:user, operator: operator, card_added: true, original_location: location).tap do |u|
      u.update_stripe_customer_id_for_location(location, "cus_window_test")
    end
  end

  let!(:single_type) do
    create(:day_pass_type, operator: operator, location: location,
           quantity: 1, amount_in_cents: 4_000, available: true, visible: true)
  end

  def auth_headers_for(u)
    payload = { user_id: u.id, operator_id: u.operator_id, exp: 1.hour.from_now.to_i }
    token = JWT.encode(payload, Rails.application.secret_key_base, "HS256")
    {
      "Authorization" => "Bearer #{token}",
      "X-Operator-Subdomain" => u.operator.subdomain,
    }
  end

  describe "POST /api/v1/day_passes" do
    it "rejects a date beyond the advance window (the wrong-year mis-tap)" do
      post "/api/v1/day_passes",
           params: { day_pass_type_id: single_type.id, date: (Date.current + 1.year).iso8601 },
           headers: auth_headers_for(user)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to include("double-check the date")
      expect(DayPass.unscoped.where(user_id: user.id)).to be_empty
    end

    it "rejects a past date" do
      post "/api/v1/day_passes",
           params: { day_pass_type_id: single_type.id, date: (Date.current - 2).iso8601 },
           headers: auth_headers_for(user)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to include("already passed")
    end

    it "rejects an unparseable date instead of 500ing" do
      post "/api/v1/day_passes",
           params: { day_pass_type_id: single_type.id, date: "not-a-date" },
           headers: auth_headers_for(user)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to include("valid date")
    end
  end

  describe "PATCH /api/v1/day_passes/:id/reschedule" do
    let!(:day_pass) do
      create(:day_pass, operator: operator, location: location, user: user,
             day_pass_type: single_type, day: Date.current)
    end

    it "rejects a target beyond the advance window" do
      patch "/api/v1/day_passes/#{day_pass.id}/reschedule",
            params: { day: (Date.current + 1.year).iso8601 },
            headers: auth_headers_for(user)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to include("double-check the date")
      expect(day_pass.reload.day).to eq(Date.current)
    end
  end
end
