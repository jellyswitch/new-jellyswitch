require "test_helper"

# DayOffices::Allocator picks a pool room and creates a $0 posted-hours hold
# for a Day Office pass (ADR 0026). Same-type allocation is serialized by
# taking FOR UPDATE on the pool's join rows; cross-type and hourly-booking
# overlaps carry no DB constraint and remain a TOCTOU window that
# ReservationValidator narrows (losing create! -> RecordInvalid -> nil) but
# does not close — accepted, consistent with the codebase's existing
# booking-race posture. See app/services/day_offices/allocator.rb.
class DayOffices::AllocatorTest < ActiveSupport::TestCase
  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @location.update!(working_day_start: "08:00", working_day_end: "18:00")
    @type = DayPassType.create!(name: "Day Office", operator: @operator, location: @location,
                                kind: "day_office", amount_in_cents: 7500, included_meeting_room_minutes: 0)
    @a = Room.create!(name: "A", operator: @operator, location: @location, visible: false)
    @b = Room.create!(name: "B", operator: @operator, location: @location)
    @type.assign_office_rooms!({ @a.id => 1, @b.id => 2 })
    @user = users(:cowork_tahoe_member)
    @other = users(:cowork_tahoe_non_member)
    @day = Date.current + 7
  end

  test "picks the first free room by position, hidden rooms included" do
    assert_equal @a, DayOffices::Allocator.available_room(day_pass_type: @type, day: @day)
  end

  test "skips a room with any overlapping reservation that day" do
    span = @location.posted_hours_span(@day)
    Reservation.create!(user: @other, room: @a, datetime_in: span.first + 2.hours, minutes: 60)
    assert_equal @b, DayOffices::Allocator.available_room(day_pass_type: @type, day: @day)
  end

  test "nil when all pool rooms are taken or pool empty / archived" do
    @a.update!(archived: true)
    span = @location.posted_hours_span(@day)
    Reservation.create!(user: @other, room: @b, datetime_in: span.first, minutes: 120)
    assert_nil DayOffices::Allocator.available_room(day_pass_type: @type, day: @day)
  end

  test "allocate! creates a $0 posted-hours hold linked to the pass" do
    pass = DayPass.create!(user: @user, billable: @user, operator: @operator,
                           location: @location, day_pass_type: @type, day: @day, imported: true)
    hold = DayOffices::Allocator.allocate!(day_pass: pass)
    span = @location.posted_hours_span(@day)
    assert_equal @a, hold.room
    assert_equal span.first, hold.datetime_in
    assert_equal 600, hold.minutes # 08:00-18:00 => 10h, literal so a regression in the duration math shows up
    assert_equal pass.id, hold.day_office_pass_id
    assert_not hold.paid
  end

  test "allocate! returns nil when nothing is free" do
    span = @location.posted_hours_span(@day)
    [@a, @b].each { |r| Reservation.create!(user: @other, room: r, datetime_in: span.first, minutes: 600) }
    pass = DayPass.create!(user: @user, billable: @user, operator: @operator,
                           location: @location, day_pass_type: @type, day: @day, imported: true)
    assert_nil DayOffices::Allocator.allocate!(day_pass: pass)
  end

  test "allocate! returns nil when the location has no usable posted hours" do
    # Overnight window: format-valid but posted_hours_span returns nil for it
    # (no relative-time validation on working_day_start/end, so a normal
    # validated update! is enough — no need to bypass validation).
    @location.update!(working_day_start: "22:00", working_day_end: "05:00")
    pass = DayPass.create!(user: @user, billable: @user, operator: @operator,
                           location: @location, day_pass_type: @type, day: @day, imported: true)
    assert_nil DayOffices::Allocator.allocate!(day_pass: pass)
  end

  test "release_hold cancels and is idempotent" do
    pass = DayPass.create!(user: @user, billable: @user, operator: @operator,
                           location: @location, day_pass_type: @type, day: @day, imported: true)
    hold = DayOffices::Allocator.allocate!(day_pass: pass)
    DayOffices::ReleaseHold.call(hold)
    assert Reservation.unscoped.find(hold.id).cancelled
    DayOffices::ReleaseHold.call(hold.reload) # second call: no error
    DayOffices::ReleaseHold.call(nil)         # nil-safe
  end

  test "allocate! is idempotent: a repeat call for the same pass returns the same hold, not a second one" do
    pass = DayPass.create!(user: @user, billable: @user, operator: @operator,
                           location: @location, day_pass_type: @type, day: @day, imported: true)
    hold1 = DayOffices::Allocator.allocate!(day_pass: pass)
    hold2 = DayOffices::Allocator.allocate!(day_pass: pass)
    assert_equal hold1.id, hold2.id
    assert_equal 1, Reservation.where(day_office_pass_id: pass.id).count
  end

  test "allocate! swallows a genuine overlap loss as nil, not raised" do
    span = @location.posted_hours_span(@day)
    # @a is taken; stub the picker to hand allocate! the taken room anyway, the
    # same shape a real concurrent-request race would produce after the lock
    # is acquired. create! must hit ReservationValidator for real here.
    Reservation.create!(user: @other, room: @a, datetime_in: span.first, minutes: 60)
    DayOffices::Allocator.stubs(:available_room).returns(@a)

    pass = DayPass.create!(user: @user, billable: @user, operator: @operator,
                           location: @location, day_pass_type: @type, day: @day, imported: true)
    assert_nil DayOffices::Allocator.allocate!(day_pass: pass)
  end

  test "allocate! raises (does not swallow) a non-overlap RecordInvalid, e.g. drifted room capacity" do
    # capacity: 0 passes Room's own validation (>= 0) — this simulates an admin
    # shrinking a pool room's capacity after it was assigned, not a bad fixture.
    zero_capacity = Room.create!(name: "Zero", operator: @operator, location: @location, capacity: 0)
    @type.assign_office_rooms!({ zero_capacity.id => 1 })

    pass = DayPass.create!(user: @user, billable: @user, operator: @operator,
                           location: @location, day_pass_type: @type, day: @day, imported: true)
    assert_raises(ActiveRecord::RecordInvalid) do
      DayOffices::Allocator.allocate!(day_pass: pass)
    end
  end

  test "sequential allocate! calls fill the pool in position order, then return nil" do
    third = users(:cowork_tahoe_admin)

    pass1 = DayPass.create!(user: @user, billable: @user, operator: @operator,
                            location: @location, day_pass_type: @type, day: @day, imported: true)
    hold1 = DayOffices::Allocator.allocate!(day_pass: pass1)
    assert_equal @a, hold1.room

    pass2 = DayPass.create!(user: @other, billable: @other, operator: @operator,
                            location: @location, day_pass_type: @type, day: @day, imported: true)
    hold2 = DayOffices::Allocator.allocate!(day_pass: pass2)
    assert_equal @b, hold2.room

    pass3 = DayPass.create!(user: third, billable: third, operator: @operator,
                            location: @location, day_pass_type: @type, day: @day, imported: true)
    assert_nil DayOffices::Allocator.allocate!(day_pass: pass3)
  end
end
