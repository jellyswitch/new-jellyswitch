require "rails_helper"

# Rack::Attack rate limits for the passwordless Login Code endpoints (ADR 0016).
# Rack::Attack is in the middleware stack in the test env (memory cache), so
# these exercise the real throttles. We clear the throttle cache before each
# example so counters don't bleed across tests.
RSpec.describe "Login Code rate limiting", type: :request do
  let!(:operator) { create(:operator, subdomain: "throttle-test") }
  let!(:location) { create(:location, operator: operator) }
  let(:headers) { { "X-Operator-Subdomain" => "throttle-test" } }

  before { Rack::Attack.cache.store.clear }

  def request_code(email)
    post "/api/v1/auth/request_login_code",
         params: { subdomain: "throttle-test", email: email },
         headers: headers
  end

  it "throttles code requests for the SAME email after 3 in the window" do
    3.times { request_code("same@example.com") }
    expect(response).not_to have_http_status(:too_many_requests)
    request_code("same@example.com")
    expect(response).to have_http_status(:too_many_requests)
  end

  it "throttles code requests per IP after 5 (distinct emails dodge the per-email cap)" do
    5.times { |i| request_code("user#{i}@example.com") }
    expect(response).not_to have_http_status(:too_many_requests)
    request_code("user6@example.com")
    expect(response).to have_http_status(:too_many_requests)
  end

  it "throttles code verification per IP after 10" do
    10.times do |i|
      post "/api/v1/auth/verify_login_code",
           params: { subdomain: "throttle-test", email: "u#{i}@example.com", code: "000000" },
           headers: headers
    end
    expect(response).not_to have_http_status(:too_many_requests)
    post "/api/v1/auth/verify_login_code",
         params: { subdomain: "throttle-test", email: "u11@example.com", code: "000000" },
         headers: headers
    expect(response).to have_http_status(:too_many_requests)
  end
end
