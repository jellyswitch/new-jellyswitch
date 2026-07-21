require "test_helper"

# GET /api/v1/onboarding_status drives the space-host chat card on the mobile
# WelcomeScreen (non-member choose + waiting-for-approval views). The card
# hides entirely when contact_name/phone/email are all blank, so the endpoint
# must resolve a host with the same fallbacks the web card uses
# (space_host_for + location contact columns) instead of returning the raw
# operator columns — which some operators never fill in.
class Api::V1::DashboardOnboardingStatusTest < ActionDispatch::IntegrationTest
  setup do
    @member   = users(:cowork_tahoe_member)
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @host     = users(:cowork_tahoe_admin)
    @token = JWT.encode(
      { user_id: @member.id, operator_id: @operator.id, exp: 30.days.from_now.to_i },
      Rails.application.secret_key_base,
      "HS256",
    )
  end

  def headers
    {
      "Authorization"        => "Bearer #{@token}",
      "X-Operator-Subdomain" => @operator.subdomain,
      "Content-Type"         => "application/json",
    }
  end

  def fetch_status
    get "/api/v1/onboarding_status", headers: headers
    assert_response :success
    JSON.parse(response.body)
  end

  test "returns the operator contact columns when they are filled in" do
    @operator.update!(contact_name: "Front Desk", contact_phone: "530-555-0101", contact_email: "desk@example.com")

    body = fetch_status
    assert_equal "Front Desk", body["contact_name"]
    assert_equal "530-555-0101", body["contact_phone"]
    assert_equal "desk@example.com", body["contact_email"]
  end

  test "falls back to the space host when the operator contact columns are blank" do
    @operator.update!(contact_name: nil, contact_phone: nil, contact_email: nil)
    @location.update!(contact_phone: nil, contact_email: nil, space_host: @host)
    @host.update!(phone: "530-555-0142")

    body = fetch_status
    assert_equal @host.name, body["contact_name"]
    assert_equal "530-555-0142", body["contact_phone"]
    assert_equal @host.email, body["contact_email"]
  end

  test "location contact columns win over the host's personal phone and email" do
    @operator.update!(contact_name: nil, contact_phone: nil, contact_email: nil)
    @location.update!(contact_phone: "530-555-0199", contact_email: "hello@example.com", space_host: @host)

    body = fetch_status
    assert_equal @host.name, body["contact_name"]
    assert_equal "530-555-0199", body["contact_phone"]
    assert_equal "hello@example.com", body["contact_email"]
  end
end
