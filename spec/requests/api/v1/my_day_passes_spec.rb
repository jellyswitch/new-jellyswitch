require "rails_helper"

RSpec.describe "GET /api/v1/my_day_passes", type: :request do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }
  let(:user)     { create(:user, operator: operator, current_location: location) }
  let(:type) do
    create(:day_pass_type, operator: operator, location: location,
           amount_in_cents: 3_000, available: true, visible: true)
  end

  def auth_headers_for(u)
    payload = { user_id: u.id, operator_id: u.operator_id, exp: 1.hour.from_now.to_i }
    token = JWT.encode(payload, Rails.application.secret_key_base, "HS256")
    {
      "Authorization"        => "Bearer #{token}",
      "X-Operator-Subdomain" => u.operator.subdomain,
    }
  end

  it "returns each pass with a human-formatted `date` AND an ISO `day` for comparison" do
    create(:day_pass, user: user, operator: operator, location: location,
           day_pass_type: type, day: Date.new(2024, 2, 2))

    get "/api/v1/my_day_passes", headers: auth_headers_for(user)

    expect(response).to have_http_status(:ok)
    pass = JSON.parse(response.body).first
    expect(pass["date"]).to eq("February  2, 2024")   # display string (unchanged)
    expect(pass["day"]).to eq("2024-02-02")           # ISO, for client-side current/past logic
  end

  it "returns 401 without auth" do
    get "/api/v1/my_day_passes"
    expect(response).to have_http_status(:unauthorized)
  end
end
