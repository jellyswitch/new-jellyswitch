require "test_helper"

# Coverage for the mobile People search bar → GET /api/v1/admin/people?q=
class Api::V1::Admin::PeopleControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin    = users(:cowork_tahoe_admin)
    @operator = operators(:cowork_tahoe)
    @token = JWT.encode(
      { user_id: @admin.id, operator_id: @operator.id, exp: 30.days.from_now.to_i },
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

  test "q filters people by name" do
    get "/api/v1/admin/people", params: { q: "Tim" }, headers: headers
    assert_response :success
    body  = JSON.parse(response.body)
    names = body["people"].map { |p| p["name"] }
    assert_includes names, "Tim C"
    refute_includes names, "Andrew N", "non-matching name should be filtered out"
    assert body["people"].all? { |p| p["name"].downcase.include?("tim") || p["email"].downcase.include?("tim") }
  end

  test "q matches email too" do
    get "/api/v1/admin/people", params: { q: "andrew@" }, headers: headers
    assert_response :success
    emails = JSON.parse(response.body)["people"].map { |p| p["email"] }
    assert_includes emails, "andrew@jellyswitch.com"
    assert emails.all? { |e| e.downcase.include?("andrew@") }
  end

  test "blank q returns the full (unfiltered) list" do
    get "/api/v1/admin/people", params: { q: "" }, headers: headers
    assert_response :success
    names = JSON.parse(response.body)["people"].map { |p| p["name"] }
    assert_includes names, "Tim C"
    assert_includes names, "Andrew N"
  end
end
