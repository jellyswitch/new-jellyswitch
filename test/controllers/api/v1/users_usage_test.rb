require "test_helper"

# GET /api/v1/me/usage backs the mobile Account screen's "My Usage" card.
# Check-ins died in Feb 2023, and the endpoint ignored door punches entirely,
# so a badge-in-only member saw all zeros. visit_days is the honest number:
# distinct days this month with a building punch, reservation, or day pass
# (Jellyswitch::UsageReport#days_used_count).
class Api::V1::UsersUsageTest < ActionDispatch::IntegrationTest
  setup do
    @member   = users(:cowork_tahoe_member)
    @operator = operators(:cowork_tahoe)

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

  test "usage reports visit_days derived from collected activity" do
    @member.checkins.destroy_all
    door = Door.create!(name: "Front Door", operator: @operator,
                        location: locations(:cowork_tahoe_location), available: true)
    DoorPunch.create!(user: @member, door: door, operator: @operator)

    get "/api/v1/me/usage", headers: headers

    assert_response :success
    body = JSON.parse(response.body)
    assert body.key?("visit_days"), "usage JSON is missing visit_days"
    assert_operator body["visit_days"], :>=, 1
  end

  test "room-lock entries alone do not create a visit day" do
    @member.checkins.destroy_all
    @member.door_punches.destroy_all
    @member.reservations.destroy_all
    @member.day_passes.destroy_all

    room = rooms(:small_meeting_room)
    lock = Door.create!(name: "Lock", operator: @operator,
                        location: locations(:cowork_tahoe_location),
                        room: room, available: true)
    DoorPunch.create!(user: @member, door: lock, operator: @operator, room_entry: true)

    get "/api/v1/me/usage", headers: headers

    assert_response :success
    assert_equal 0, JSON.parse(response.body)["visit_days"]
  end
end
