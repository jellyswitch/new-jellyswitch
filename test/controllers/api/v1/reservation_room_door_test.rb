require "test_helper"

# "The reservation is the key" (ADR 0021): the booking payload carries its
# room's lock + whether it is unlockable right now, so the app renders the
# Unlock button on the booking card.
class Api::V1::ReservationRoomDoorTest < ActionDispatch::IntegrationTest
  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @member   = users(:cowork_tahoe_member)
    @room     = rooms(:small_meeting_room)
    @room.reservations.delete_all
    @lock = Door.create!(name: "Meeting Room Lock", operator: @operator,
                         location: @location, room: @room, kisi_id: 99997, available: true)
    @token = JWT.encode({ user_id: @member.id, operator_id: @operator.id, exp: 30.days.from_now.to_i },
                        Rails.application.secret_key_base, "HS256")
  end

  def headers
    { "Authorization" => "Bearer #{@token}", "X-Operator-Subdomain" => @operator.subdomain }
  end

  # The index nests bookings under ongoing/upcoming/past/team — flatten the
  # member-owned groups to find ours.
  def find_reservation(room_id)
    body = JSON.parse(response.body)
    (body["ongoing"] + body["upcoming"] + body["past"]).find { |r| r["room_id"] == room_id }
  end

  test "an ongoing reservation exposes its unlockable room door" do
    Reservation.create!(user: @member, room: @room, datetime_in: 10.minutes.ago, minutes: 60)
    get "/api/v1/reservations", headers: headers
    assert_response :success
    res = find_reservation(@room.id)
    assert_equal @lock.id, res["room_door_id"]
    assert_equal @lock.name, res["room_door_name"]
    assert_equal true, res["room_door_unlockable"]
  end

  test "a far-future reservation carries the door but not unlockable" do
    Reservation.create!(user: @member, room: @room, datetime_in: 3.hours.from_now, minutes: 60)
    get "/api/v1/reservations", headers: headers
    assert_response :success
    res = find_reservation(@room.id)
    assert_equal @lock.id, res["room_door_id"]
    assert_equal false, res["room_door_unlockable"]
  end
end
