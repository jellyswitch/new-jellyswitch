require "test_helper"

# ADR 0021 authorization matrix for Room Locks (doors attached to a Room):
# holder-during-booking + staff only; coverage alone opens Building Doors
# but never a Room Lock; Room Entries don't burn bundle passes.
class Api::V1::RoomLockUnlockTest < ActionDispatch::IntegrationTest
  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @member   = users(:cowork_tahoe_member)
    @admin    = users(:cowork_tahoe_admin)
    @room     = rooms(:small_meeting_room)
    @room.reservations.delete_all

    @lock = Door.create!(name: "Meeting Room Lock", operator: @operator,
                         location: @location, room: @room, kisi_id: 99999, available: true)

    # Unlock hits Kisi — stub with webmock like doors_controller_test does.
    stub_kisi(@lock)
  end

  def stub_kisi(door)
    stub_request(:post, "https://api.kisi.io/locks/#{door.kisi_id}/unlock").to_return(
      status:  200,
      body:    { success: true, lock_id: door.kisi_id }.to_json,
      headers: { "Content-Type" => "application/json" },
    )
  end

  def headers_for(user)
    token = JWT.encode({ user_id: user.id, operator_id: @operator.id, exp: 30.days.from_now.to_i },
                       Rails.application.secret_key_base, "HS256")
    { "Authorization" => "Bearer #{token}", "X-Operator-Subdomain" => @operator.subdomain }
  end

  def reserve(user, starts_at, minutes: 60)
    # validate: false — ReservationValidator rejects overlaps, and the
    # early-grace matrix needs a deliberately colliding prior booking.
    Reservation.new(user: user, room: @room, datetime_in: starts_at, minutes: minutes)
      .tap { |r| r.save!(validate: false) }
  end

  test "covered member WITHOUT a reservation cannot open a room lock" do
    post "/api/v1/doors/#{@lock.id}/unlock", headers: headers_for(@member)
    assert_response :forbidden
    assert_match(/opens with a reservation/, JSON.parse(response.body)["message"])
  end

  test "the reservation holder opens the lock during their booking" do
    reserve(@member, 10.minutes.ago)
    post "/api/v1/doors/#{@lock.id}/unlock", headers: headers_for(@member)
    assert_response :success
    assert JSON.parse(response.body)["success"]
  end

  test "holder within the early grace opens the lock when the room is free" do
    reserve(@member, 5.minutes.from_now)
    post "/api/v1/doors/#{@lock.id}/unlock", headers: headers_for(@member)
    assert_response :success
  end

  test "early grace is denied while a prior booking still occupies the room" do
    reserve(@admin, 30.minutes.ago, minutes: 40)   # still running
    reserve(@member, 5.minutes.from_now)
    post "/api/v1/doors/#{@lock.id}/unlock", headers: headers_for(@member)
    assert_response :forbidden
  end

  test "the holder cannot open the lock after their booking ends" do
    reserve(@member, 2.hours.ago, minutes: 60)
    post "/api/v1/doors/#{@lock.id}/unlock", headers: headers_for(@member)
    assert_response :forbidden
  end

  test "staff open a room lock anytime" do
    post "/api/v1/doors/#{@lock.id}/unlock", headers: headers_for(@admin)
    assert_response :success
  end

  test "a room-lock open is a Room Entry and never burns a bundle pass" do
    reserve(@member, 10.minutes.ago)
    Billing::DayPassBundles::ConsumeOnEntry.expects(:call).never

    post "/api/v1/doors/#{@lock.id}/unlock", headers: headers_for(@member)
    assert_response :success
    assert DoorPunch.where(door: @lock, user: @member).all?(&:room_entry),
      "room-lock punches must be flagged room_entry"
  end

  test "building doors keep coverage gating and punch semantics" do
    building_door = Door.create!(name: "Front", operator: @operator,
                                 location: @location, kisi_id: 99998, available: true)
    stub_kisi(building_door)
    post "/api/v1/doors/#{building_door.id}/unlock", headers: headers_for(@member)
    assert_response :success
    refute DoorPunch.where(door: building_door, user: @member).any?(&:room_entry)
  end

  test "members' Keys list excludes room locks; admins keep them" do
    get "/api/v1/doors", headers: headers_for(@member)
    refute_includes JSON.parse(response.body).map { |d| d["id"] }, @lock.id

    get "/api/v1/doors", headers: headers_for(@admin)
    assert_includes JSON.parse(response.body).map { |d| d["id"] }, @lock.id
  end
end
