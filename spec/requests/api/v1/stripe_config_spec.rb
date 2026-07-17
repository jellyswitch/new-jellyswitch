require "rails_helper"

# Regression: locations.stripe_publishable_key (a DB column written by Stripe
# Connect OAuth) holds the connected account's live-mode key. A prod snapshot
# copied to staging served pk_live against test-mode secret keys, so mobile
# clients minted live tokens the server couldn't consume. The endpoint must
# serve the env-configured platform key, mode-matched to stripe_secret_key.
RSpec.describe "GET /api/v1/stripe_config", type: :request do
  let(:operator) { create(:operator) }
  let(:location) do
    create(:location, operator: operator,
           stripe_user_id: "acct_1", stripe_publishable_key: "pk_live_from_connect_oauth")
  end
  let(:user) { create(:user, operator: operator, current_location: location) }

  def auth_headers_for(u)
    payload = { user_id: u.id, operator_id: u.operator_id, exp: 1.hour.from_now.to_i }
    token = JWT.encode(payload, Rails.application.secret_key_base, "HS256")
    {
      "Authorization"        => "Bearer #{token}",
      "X-Operator-Subdomain" => u.operator.subdomain,
    }
  end

  before do
    allow(Rails.configuration).to receive(:stripe).and_return(
      publishable_key: "pk_live_platform",
      test_publishable_key: "pk_test_platform",
    )
  end

  it "serves the env-configured platform key, never the DB column" do
    operator.update!(billing_state: "production")

    get "/api/v1/stripe_config", headers: auth_headers_for(user)

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["publishable_key"]).to eq("pk_live_platform")
    expect(body["account_id"]).to eq("acct_1")
  end

  it "serves the test key for non-production operators" do
    operator.update!(billing_state: "demo")

    get "/api/v1/stripe_config", headers: auth_headers_for(user)

    expect(JSON.parse(response.body)["publishable_key"]).to eq("pk_test_platform")
  end
end
