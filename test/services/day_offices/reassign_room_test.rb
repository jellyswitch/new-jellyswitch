require "test_helper"

# DayOffices::ReassignRoom is the admin-only narrow move (Task 12, ADR 0026
# decision #8): any ACTIVE room at the hold's location — hidden included — that
# is free for the hold's exact window. Notifies the member only after a
# successful write; every refusal path must enqueue nothing.
class DayOffices::ReassignRoomTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper

  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @location.update!(time_zone: "Pacific Time (US & Canada)",
                      working_day_start: "08:00", working_day_end: "18:00")
    @type = DayPassType.create!(name: "Day Office", operator: @operator, location: @location,
                                kind: "day_office", amount_in_cents: 7500, included_meeting_room_minutes: 0)
    @a = Room.create!(name: "Office A", operator: @operator, location: @location)
    @b = Room.create!(name: "Office B", operator: @operator, location: @location)
    @type.assign_office_rooms!({ @a.id => 1, @b.id => 2 })
    @user = users(:cowork_tahoe_member)
    @other = users(:cowork_tahoe_non_member)
    @day = Date.current + 7
  end

  # Returns [pass, hold]. Allocator fills position order, so a fresh pass
  # always lands on @a first — the sanity anchor every test below relies on.
  def office_pass!(day: @day, user: @user)
    pass = DayPass.create!(user: user, billable: user, operator: @operator, location: @location,
                           day_pass_type: @type, day: day, imported: true)
    [pass, DayOffices::Allocator.allocate!(day_pass: pass)]
  end

  # --- happy path ----------------------------------------------------------

  test "moves the hold to the target room and notifies the member exactly once with the old room's name" do
    _pass, hold = office_pass!
    assert_equal @a, hold.room # sanity: allocator picked the position-1 room

    result = nil
    # assert_enqueued_jobs 1, not just assert_enqueued_with: pins that the
    # push fires exactly once per move, not merely "at least once".
    assert_enqueued_jobs 1, only: SendNotificationsJob do
      assert_enqueued_with(job: SendNotificationsJob, args: [hold, "DayOfficeReassigned"]) do
        assert_enqueued_email_with UserMailer, :day_office_reassigned, args: [hold.id, "Office A"] do
          result = DayOffices::ReassignRoom.call(hold: hold, room: @b)
        end
      end
    end
    assert result.ok?
    assert_nil result.error
    assert result.moved?

    assert_equal @b, hold.reload.room
  end

  test "frees the old room so a new booking can take it immediately" do
    _pass, hold = office_pass!
    result = DayOffices::ReassignRoom.call(hold: hold, room: @b)
    assert result.ok?

    span = @location.posted_hours_span(@day)
    assert_nothing_raised do
      Reservation.create!(user: @other, room: @a, datetime_in: span.first, minutes: 60)
    end
  end

  test "moves to a hidden room — an admin override, unlike member self-service" do
    _pass, hold = office_pass!
    @b.update!(visible: false)

    result = DayOffices::ReassignRoom.call(hold: hold, room: @b)

    assert result.ok?
    assert_equal @b, hold.reload.room
  end

  # --- same-room no-op -------------------------------------------------------

  test "reassigning to the hold's current room is a no-op: ok, unchanged, no notification" do
    _pass, hold = office_pass!

    assert_no_enqueued_jobs do
      result = DayOffices::ReassignRoom.call(hold: hold, room: @a)
      assert result.ok?
      assert_nil result.error
      assert_not result.moved?
    end

    assert_equal @a, hold.reload.room
  end

  # --- refusals — each must enqueue nothing and leave the hold untouched ---

  test "refuses an occupied target room" do
    _pass, hold = office_pass!
    span = @location.posted_hours_span(@day)
    Reservation.create!(user: @other, room: @b, datetime_in: span.first, minutes: 60)

    result = nil
    assert_no_enqueued_jobs do
      result = DayOffices::ReassignRoom.call(hold: hold, room: @b)
    end

    assert_not result.ok?
    assert_match(/Office B is already booked/i, result.error)
    assert_equal @a, hold.reload.room
  end

  test "refuses a room at a different location" do
    other_location = create(:location, operator: @operator, name: "Other Site")
    cross_room = Room.create!(name: "Cross-site Room", operator: @operator, location: other_location)
    _pass, hold = office_pass!

    result = nil
    assert_no_enqueued_jobs do
      result = DayOffices::ReassignRoom.call(hold: hold, room: cross_room)
    end

    assert_not result.ok?
    assert_match(/not found at this location/i, result.error)
    assert_equal @a, hold.reload.room
  end

  test "refuses an archived room" do
    _pass, hold = office_pass!
    @b.update!(archived: true)

    result = nil
    assert_no_enqueued_jobs do
      result = DayOffices::ReassignRoom.call(hold: hold, room: @b)
    end

    assert_not result.ok?
    assert_match(/not found at this location/i, result.error)
    assert_equal @a, hold.reload.room
  end

  test "refuses a missing room (nil)" do
    _pass, hold = office_pass!

    result = DayOffices::ReassignRoom.call(hold: hold, room: nil)

    assert_not result.ok?
    assert_match(/not found at this location/i, result.error)
  end

  test "refuses a reservation that is not a Day Office hold" do
    ordinary = Reservation.create!(user: @user, room: @a, datetime_in: 1.day.from_now, minutes: 60)

    result = nil
    assert_no_enqueued_jobs do
      result = DayOffices::ReassignRoom.call(hold: ordinary, room: @b)
    end

    assert_not result.ok?
    assert_match(/not a day office hold/i, result.error)
    assert_equal @a, ordinary.reload.room
  end

  test "refuses a nil hold" do
    result = DayOffices::ReassignRoom.call(hold: nil, room: @b)

    assert_not result.ok?
    assert_match(/no longer active/i, result.error)
  end

  # --- liveness guard: a released or ended hold is not a live thing to move ---

  test "refuses a cancelled hold" do
    _pass, hold = office_pass!
    hold.update_columns(cancelled: true) # ReleaseHold's own idiom — bypasses validation

    result = nil
    assert_no_enqueued_jobs do
      result = DayOffices::ReassignRoom.call(hold: hold, room: @b)
    end

    assert_not result.ok?
    assert_match(/no longer active/i, result.error)
  end

  test "refuses a hold whose window has already ended" do
    _pass, hold = office_pass!
    hold.update_columns(datetime_in: 2.days.ago, minutes: 60) # ended well before now
    assert hold.datetime_out <= Time.current, "sanity: window is in the past"

    result = nil
    assert_no_enqueued_jobs do
      result = DayOffices::ReassignRoom.call(hold: hold, room: @b)
    end

    assert_not result.ok?
    assert_match(/no longer active/i, result.error)
  end

  test "reassigns fine for an ongoing hold whose window has not yet ended" do
    _pass, hold = office_pass!
    hold.update_columns(datetime_in: 30.minutes.ago, minutes: 120) # started, ends in 90 more minutes
    assert hold.datetime_out > Time.current, "sanity: still ongoing, not yet ended"

    result = DayOffices::ReassignRoom.call(hold: hold, room: @b)

    assert result.ok?
    assert result.moved?
    assert_equal @b, hold.reload.room
  end

  # capacity-0 decision: hold.update! re-runs attendee_count_within_capacity
  # (the hold carries attendee_count: 1). A pool room whose capacity got
  # edited down to 0 after assignment must REFUSE with a readable message,
  # not raise — mirrors the Room fixture Allocator's own capacity-drift test
  # uses ("capacity: 0 passes Room's own validation >= 0").
  test "refuses a capacity-0 target with a readable error instead of raising" do
    _pass, hold = office_pass!
    zero = Room.create!(name: "Zero", operator: @operator, location: @location, capacity: 0)

    result = nil
    assert_nothing_raised do
      assert_no_enqueued_jobs do
        result = DayOffices::ReassignRoom.call(hold: hold, room: zero)
      end
    end

    assert_not result.ok?
    assert_match(/capacity/i, result.error)
    assert_equal @a, hold.reload.room, "the failed update must not have partially applied"
  end

  # --- notification ordering ------------------------------------------------

  test "no refusal path ever enqueues a notification" do
    _pass, hold = office_pass!
    span = @location.posted_hours_span(@day)
    Reservation.create!(user: @other, room: @b, datetime_in: span.first, minutes: 60) # occupies @b

    assert_no_enqueued_jobs do
      DayOffices::ReassignRoom.call(hold: hold, room: @b)          # occupied
      DayOffices::ReassignRoom.call(hold: hold, room: nil)         # missing room
      DayOffices::ReassignRoom.call(hold: hold, room: hold.room)   # same-room no-op
      DayOffices::ReassignRoom.call(hold: nil, room: @b)           # nil hold
    end
  end

  # --- options_for (Task 14): the reassign picker's candidate query --------
  # Parity coverage with Api::V1::Admin::ReservationsControllerTest's
  # "reassign_options lists free rooms, flags hidden, and excludes the
  # current/occupied/archived rooms" — same query, now exercised directly at
  # the service layer since the web profile calls it without going through
  # that controller action.

  test "options_for offers a free room (hidden included) and excludes the current/occupied/archived rooms" do
    _pass, hold = office_pass!
    assert_equal @a, hold.room # sanity: allocator picked the position-1 room

    hidden_room   = Room.create!(name: "Hidden Office", operator: @operator, location: @location, visible: false)
    occupied_room = Room.create!(name: "Occupied Office", operator: @operator, location: @location)
    archived_room = Room.create!(name: "Archived Office", operator: @operator, location: @location, archived: true)
    Reservation.create!(user: @other, room: occupied_room, datetime_in: hold.datetime_in, minutes: hold.minutes)

    ids = DayOffices::ReassignRoom.options_for(hold).map(&:id)

    assert_includes ids, @b.id, "the pool's other free room must be offered"
    assert_includes ids, hidden_room.id, "a hidden room must still be offered to an admin"
    refute_includes ids, @a.id, "the hold's current room must not be offered as a target"
    refute_includes ids, occupied_room.id
    refute_includes ids, archived_room.id
  end

  test "options_for returns actual Room records, not just ids, ordered by name" do
    _pass, hold = office_pass!
    early = Room.create!(name: "AAA First", operator: @operator, location: @location)

    rooms = DayOffices::ReassignRoom.options_for(hold)

    assert_kind_of Room, rooms.first
    assert_equal early, rooms.first, "order(:name) should sort this room to the front"
  end
end
