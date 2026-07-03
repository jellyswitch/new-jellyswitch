require "test_helper"

# A room taken between the room list loading and the member's Confirm tap
# must come back as 409 + {error, conflict:{room_name, window_label}} — the
# app shows "Just missed it" and refreshes the list. Older bundles render
# data.error raw, so the sentence itself must carry room + window.
class Api::V1::ReservationsConflictTest < ActionDispatch::IntegrationTest
  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @member   = users(:cowork_tahoe_member)
    @rival    = users(:cowork_tahoe_admin)
    @room     = rooms(:small_meeting_room)
    @room.reservations.delete_all
    @zone = ActiveSupport::TimeZone[@location.time_zone]
    day = Date.current + 7
    @start = @zone.local(day.year, day.month, day.day, 10)
    Reservation.create!(user: @rival, room: @room, datetime_in: @start, minutes: 60)

    @token = JWT.encode({ user_id: @member.id, operator_id: @operator.id, exp: 30.days.from_now.to_i },
                        Rails.application.secret_key_base, "HS256")
  end

  def headers
    { "Authorization" => "Bearer #{@token}",
      "X-Operator-Subdomain" => @operator.subdomain,
      "Content-Type" => "application/json" }
  end

  test "create against a taken slot returns 409 with room + window" do
    post "/api/v1/reservations",
         params: { reservation: { room_id: @room.id,
                                  datetime_in: @start.strftime("%Y-%m-%dT%H:%M:%S"),
                                  minutes: 60 } }.to_json,
         headers: headers

    assert_response :conflict
    body = JSON.parse(response.body)
    assert_equal "#{@room.name} is no longer free 10:00–11:00 AM.", body["error"]
    assert_equal @room.name, body.dig("conflict", "room_name")
    assert_equal "10:00–11:00 AM", body.dig("conflict", "window_label")
  end

  test "update into a taken slot returns 409 with conflict payload" do
    mine = Reservation.create!(user: @member, room: @room,
      datetime_in: @start + 3.hours, minutes: 60)

    patch "/api/v1/reservations/#{mine.id}",
          params: { reservation: { datetime_in: @start.strftime("%Y-%m-%dT%H:%M:%S"),
                                   minutes: 60 } }.to_json,
          headers: headers

    assert_response :conflict
    body = JSON.parse(response.body)
    assert_equal "10:00–11:00 AM", body.dig("conflict", "window_label")
    # The persisted row is untouched by the failed edit.
    assert_equal (@start + 3.hours).to_i, mine.reload.datetime_in.to_i
  end
end
