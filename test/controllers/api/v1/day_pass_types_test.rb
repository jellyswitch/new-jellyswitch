require "test_helper"

class Api::V1::DayPassTypesTest < ActionDispatch::IntegrationTest
  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @user     = users(:cowork_tahoe_non_member)
  end

  def headers
    token = JWT.encode({ user_id: @user.id, operator_id: @operator.id, exp: 30.days.from_now.to_i },
                       Rails.application.secret_key_base, "HS256")
    { "Authorization" => "Bearer #{token}", "X-Operator-Subdomain" => @operator.subdomain }
  end

  test "types carries the room-booking default flag and included minutes" do
    DayPassType.create!(operator: @operator, location: @location, name: "Coworking Day Pass",
                        amount_in_cents: 4000, visible: true, available: true,
                        included_meeting_room_minutes: 180, default_for_room_booking: true)

    get "/api/v1/day_pass_types", headers: headers
    assert_response :success
    type = JSON.parse(response.body).find { |t| t["name"] == "Coworking Day Pass" }
    assert_equal true, type["default_for_room_booking"]
    assert_equal 180, type["included_meeting_minutes"]
    assert_equal 4000, type["price"]
  end
end
