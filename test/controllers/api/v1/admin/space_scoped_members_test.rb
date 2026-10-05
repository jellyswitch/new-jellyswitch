require "test_helper"

# Seth (Untethered Fulton, 10/5): the mobile admin Members and People lists
# showed Lake Tahoe members too. Untethered runs both spaces under one
# operator; each list is now limited to the admin's current space.
class Api::V1::Admin::SpaceScopedMembersTest < ActionDispatch::IntegrationTest
  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @admin    = users(:cowork_tahoe_admin)

    @other = @location.dup
    @other.name = "Second Space"
    @other.save!(validate: false)

    attrs = { operator: @operator, approved: true, phone: "5305550111", password: "password123", admin_created: true }
    @here         = User.create!(attrs.merge(name: "Here Person", email: "here-person@example.com", original_location: @location))
    @there        = User.create!(attrs.merge(name: "Other Space Person", email: "other-person@example.com", original_location: @other))
    @there_gone   = User.create!(attrs.merge(name: "Other Space Archived", email: "other-archived@example.com", original_location: @other, archived: true))

    @token = JWT.encode({ user_id: @admin.id, operator_id: @operator.id, exp: 30.days.from_now.to_i },
                        Rails.application.secret_key_base, "HS256")
  end

  def headers
    { "Authorization" => "Bearer #{@token}", "X-Operator-Subdomain" => @operator.subdomain,
      "Content-Type" => "application/json" }
  end

  test "members list only shows the current space" do
    get "/api/v1/admin/members", params: { q: "Person" }, headers: headers
    assert_response :success
    names = JSON.parse(response.body).map { |m| m["name"] }
    assert_includes names, "Here Person"
    assert_not_includes names, "Other Space Person"
  end

  test "archived members list only shows the current space" do
    get "/api/v1/admin/members/archived", headers: headers
    assert_response :success
    assert_not_includes JSON.parse(response.body).map { |m| m["name"] }, "Other Space Archived"
  end

  test "people list only shows the current space" do
    get "/api/v1/admin/people", params: { q: "Person" }, headers: headers
    assert_response :success
    names = JSON.parse(response.body)["people"].map { |p| p["name"] }
    assert_includes names, "Here Person"
    assert_not_includes names, "Other Space Person"
  end
end
