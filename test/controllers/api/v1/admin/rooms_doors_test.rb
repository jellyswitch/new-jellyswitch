require "test_helper"

# Door↔Room configuration (ADR 0021): a room's locks are assigned by sending
# the full door_ids list on room update; omitted doors detach (become
# Building Doors again). Reassignment is scoped to the room's location.
class Api::V1::Admin::RoomsDoorsTest < ActionDispatch::IntegrationTest
  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @admin    = users(:cowork_tahoe_admin)
    @room     = rooms(:small_meeting_room)
    @door     = Door.create!(name: "Lock A", operator: @operator, location: @location, available: true)
    @token = JWT.encode({ user_id: @admin.id, operator_id: @operator.id, exp: 30.days.from_now.to_i },
                        Rails.application.secret_key_base, "HS256")
  end

  def headers
    { "Authorization" => "Bearer #{@token}", "X-Operator-Subdomain" => @operator.subdomain,
      "Content-Type" => "application/json" }
  end

  test "assigning and clearing a room's locks via door_ids" do
    patch "/api/v1/admin/rooms/#{@room.id}",
          params: { room: { door_ids: [@door.id] } }.to_json, headers: headers
    assert_response :success
    assert_equal @room.id, @door.reload.room_id
    assert_includes JSON.parse(response.body)["door_ids"], @door.id

    patch "/api/v1/admin/rooms/#{@room.id}",
          params: { room: { door_ids: [] } }.to_json, headers: headers
    assert_response :success
    assert_nil @door.reload.room_id
  end

  test "cannot attach another location's door" do
    other_location = Location.create!(name: "Annex", operator: @operator,
                                      working_day_start: "06:00", working_day_end: "20:00")
    other_door = Door.create!(name: "Annex Door", operator: @operator,
                              location: other_location, available: true)

    patch "/api/v1/admin/rooms/#{@room.id}",
          params: { room: { door_ids: [other_door.id] } }.to_json, headers: headers
    assert_response :success
    assert_nil other_door.reload.room_id, "attached a door across locations"
  end
end
