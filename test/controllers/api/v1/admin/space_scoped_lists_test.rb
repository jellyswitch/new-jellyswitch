require "test_helper"

# Untethered runs two spaces (Lake Tahoe + Fulton) under one operator. Seth
# (Fulton, 2026-10-03): the mobile admin Doors and Groups lists, and the web
# group "Add members" picker, mixed both spaces. Each list is now per space.
class Api::V1::Admin::SpaceScopedListsTest < ActionDispatch::IntegrationTest
  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @admin    = users(:cowork_tahoe_admin)

    @other = @location.dup
    @other.name = "Second Space"
    @other.save!(validate: false)

    @here_door  = Door.create!(name: "Here Door", operator: @operator, location: @location, available: true)
    @other_door = Door.create!(name: "Other Space Door", operator: @operator, location: @other, available: true)

    @here_org  = Organization.create!(name: "Here Group", operator: @operator, location: @location)
    @other_org = Organization.create!(name: "Other Space Group", operator: @operator, location: @other)

    @token = JWT.encode({ user_id: @admin.id, operator_id: @operator.id, exp: 30.days.from_now.to_i },
                        Rails.application.secret_key_base, "HS256")
  end

  def headers
    { "Authorization" => "Bearer #{@token}", "X-Operator-Subdomain" => @operator.subdomain,
      "Content-Type" => "application/json" }
  end

  test "mobile admin doors list only shows the current space's doors" do
    get "/api/v1/admin/doors", headers: headers
    assert_response :success
    names = JSON.parse(response.body).map { |d| d["name"] }
    assert_includes names, "Here Door"
    assert_not_includes names, "Other Space Door"
  end

  test "mobile admin groups list only shows the current space's groups" do
    get "/api/v1/admin/organizations", headers: headers
    assert_response :success
    names = JSON.parse(response.body).map { |o| o["name"] }
    assert_includes names, "Here Group"
    assert_not_includes names, "Other Space Group"
  end
end
