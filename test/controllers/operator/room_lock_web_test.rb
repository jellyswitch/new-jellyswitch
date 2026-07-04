require "test_helper"

# ADR 0021 on the WEB surfaces (review-added hardening): the Keys page's
# unlock endpoint (/api/doors/:id/unlock), the legacy operator open action
# (/doors/:id/open), and the member-facing keys lists must all treat Room
# Locks as reservation-gated — same rule as api/v1, via
# Door#openable_as_room_lock_by?.
class Operator::RoomLockWebTest < ActionDispatch::IntegrationTest
  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @member   = users(:cowork_tahoe_member)
    @admin    = users(:cowork_tahoe_admin)
    @room     = rooms(:small_meeting_room)
    @room.reservations.delete_all

    @lock = Door.create!(name: "Meeting Room Lock", operator: @operator,
                         location: @location, room: @room, kisi_id: 99996, available: true)
    stub_request(:post, "https://api.kisi.io/locks/#{@lock.kisi_id}/unlock").to_return(
      status:  200,
      body:    { success: true, lock_id: @lock.kisi_id }.to_json,
      headers: { "Content-Type" => "application/json" },
    )
  end

  # --- /api/doors/:id/unlock — the endpoint the web Keys page buttons hit ---

  test "web unlock: covered member without a reservation is denied on a room lock" do
    log_in @member

    post "/api/doors/#{@lock.id}/unlock", env: default_env
    assert_response :forbidden
    assert_match(/opens with a reservation/, JSON.parse(response.body)["message"])
    assert_empty DoorPunch.where(door: @lock), "denied unlock must not log a punch"
  end

  test "web unlock: the reservation holder opens the lock and it is a Room Entry" do
    Reservation.create!(user: @member, room: @room, datetime_in: 10.minutes.ago, minutes: 60)
    log_in @member

    post "/api/doors/#{@lock.id}/unlock", env: default_env
    assert_response :success
    assert JSON.parse(response.body)["success"]
    punches = DoorPunch.where(door: @lock, user: @member)
    assert punches.any? && punches.all?(&:room_entry), "web room-lock punches must be flagged room_entry"
  end

  test "web unlock: staff open a room lock anytime" do
    log_in @admin

    post "/api/doors/#{@lock.id}/unlock", env: default_env
    assert_response :success
    assert JSON.parse(response.body)["success"]
    assert DoorPunch.where(door: @lock, user: @admin).all?(&:room_entry)
  end

  # --- legacy /doors/:door_id/open (operator/doors#open) ---

  test "legacy open action: member without a reservation is denied on a room lock" do
    log_in @member

    get "/doors/#{@lock.slug}/open", env: default_env
    assert_response :redirect
    assert_match(/opens with a reservation/, flash[:error])
    assert_empty DoorPunch.where(door: @lock), "denied open must not log a punch"
  end

  test "legacy open action: staff open a room lock and the punch is a Room Entry" do
    log_in @admin

    get "/doors/#{@lock.slug}/open", env: default_env
    assert_response :redirect
    assert_nil flash[:error]
    punches = DoorPunch.where(door: @lock, user: @admin)
    assert punches.any? && punches.all?(&:room_entry)
  end

  # --- member-facing keys lists ---

  test "web Keys page excludes room locks for members but keeps building doors" do
    front = Door.create!(name: "Front Door", operator: @operator,
                         location: @location, kisi_id: 99995, available: true)
    log_in @member

    get "/doors/keys", env: default_env
    assert_response :success
    refute_match @lock.name, response.body
    assert_match front.name, response.body
  end

  test "staff doors index keeps room locks" do
    log_in @admin

    get "/doors", env: default_env
    assert_response :success
    assert_match @lock.name, response.body
  end
end
