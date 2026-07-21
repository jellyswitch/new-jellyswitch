require "test_helper"

class Operator::RoomsControllerTest < ActionDispatch::IntegrationTest
  setup do
    setup_initial_user_fixtures
    @room = rooms(:small_meeting_room)
  end

  # Regression: Tahoe Longhouse lockout. A Pundit denial on room update must be
  # handled by the framework's clean user_not_authorized handler, not swallowed
  # by the controller's broad `rescue Exception` — which surfaced the raw
  # "not allowed to RoomPolicy#update? this Room" message to the end user.
  test "denied room update is handled cleanly without leaking the policy name" do
    log_in users(:cowork_tahoe_member)

    patch room_path(@room, params: { room: { name: "Hijacked" } }), env: default_env

    assert_no_match(/RoomPolicy/, flash.to_h.values.join(" "),
      "Pundit policy internals must not leak into a user-facing flash")
    assert_no_match(/An error occurred/, flash.to_h.values.join(" "))
    assert_equal "Meeting Room 3B", @room.reload.name
  end

  # Regression: submitting the room form with a blanked capacity used to hit
  # Postgres as a NotNullViolation — a raw "An error occurred: PG::..." flash
  # and a Honeybadger alert (Tahoe Longhouse "Meeting Room", 2026-07-20). The
  # model validation must turn it into a field error and keep the old value.
  test "update with a blank capacity shows a validation error instead of crashing" do
    log_in users(:cowork_tahoe_admin)
    original_capacity = @room.capacity

    patch room_path(@room), env: default_env, params: {
      room: { name: @room.name, capacity: "", hourly_rate_in_cents: "0" },
    }

    assert_match(/Capacity can't be blank/, flash.to_h.values.join(" "))
    assert_no_match(/An error occurred/, flash.to_h.values.join(" "),
      "a blank capacity must be a validation error, not a rescued exception")
    assert_equal original_capacity, @room.reload.capacity
  end

  # ADR 0012: the per-room "Counts toward day pass (call room)" toggle must be
  # permitted and persisted by the operator room form.
  test "update persists include_with_day_pass" do
    log_in users(:cowork_tahoe_admin)
    @room.update!(include_with_day_pass: false)

    patch room_path(@room), env: default_env, params: {
      room: { name: @room.name, hourly_rate_in_cents: "0", include_with_day_pass: "1" },
    }

    assert @room.reload.include_with_day_pass,
      "the call-room toggle must be saved through room_params"
  end

  # ADR 0021: the room form assigns/clears the room's electric locks via
  # door_ids (full-list semantics; a hidden blank entry means "clear all").
  test "update assigns and clears the room's door locks" do
    log_in users(:cowork_tahoe_admin)
    door = Door.create!(name: "Lock W", operator: operators(:cowork_tahoe),
                        location: locations(:cowork_tahoe_location), available: true)

    patch room_path(@room), env: default_env, params: {
      room: { name: @room.name, hourly_rate_in_cents: "0", door_ids: ["", door.id.to_s] },
    }
    assert_equal @room.id, door.reload.room_id, "checked door was not attached"

    patch room_path(@room), env: default_env, params: {
      room: { name: @room.name, hourly_rate_in_cents: "0", door_ids: [""] },
    }
    assert_nil door.reload.room_id, "unchecking all boxes must detach the lock"
  end

  test "edit form renders the door locks section" do
    log_in users(:cowork_tahoe_admin)
    Door.create!(name: "Lock X", operator: operators(:cowork_tahoe),
                 location: locations(:cowork_tahoe_location), available: true)

    get edit_room_path(@room), env: default_env
    assert_response :success
    assert_match "Door locks", response.body
    assert_match "Lock X", response.body
  end

  # A beacon-linked door is an arrival-unlock building entrance; the picker
  # must warn before it can be attached as a room lock (ADR 0021 — the TLH
  # front-door lockout). Plain doors must NOT carry the warning.
  test "edit form warns on beacon-linked doors only" do
    log_in users(:cowork_tahoe_admin)
    operator = operators(:cowork_tahoe)
    location = locations(:cowork_tahoe_location)
    entrance = Door.create!(name: "Front Entrance", operator: operator,
                            location: location, available: true)
    Beacon.create!(name: "Entrance Beacon", uuid: SecureRandom.uuid, major: 9, minor: 9,
                   operator: operator, location: location, door: entrance)
    plain = Door.create!(name: "Lock Y", operator: operator,
                         location: location, available: true)

    get edit_room_path(@room), env: default_env
    assert_response :success
    assert_match "arrival-unlock beacon", response.body

    body = Nokogiri::HTML(response.body)
    assert body.at_css("#room_door_#{entrance.id}")["data-beacon-warning"].present?,
      "beacon-linked door checkbox must carry the confirm warning"
    assert body.at_css("#room_door_#{plain.id}")["data-beacon-warning"].blank?,
      "plain door checkbox must not prompt"
  end
end
