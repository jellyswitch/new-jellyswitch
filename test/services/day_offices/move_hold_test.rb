require "test_helper"

# DayOffices::MoveHold atomically moves a Day Office pass's hold to a new
# date (Task 9, ADR 0026): release the OLD hold, move the pass, allocate on
# the NEW date — all inside one transaction, so a full target date rolls
# everything back (the old hold's release included) and nothing changes.
#
# Release-before-allocate is load-bearing: Allocator.allocate!'s idempotency
# guard returns ANY live hold for the pass regardless of date, so allocating
# before releasing would just hand back the old-date hold and silently not
# move it. See app/services/day_offices/move_hold.rb.
class DayOffices::MoveHoldTest < ActiveSupport::TestCase
  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @type = DayPassType.create!(name: "Day Office", operator: @operator, location: @location,
                                kind: "day_office", amount_in_cents: 7500, included_meeting_room_minutes: 0)
    @a = Room.create!(name: "A", operator: @operator, location: @location)
    @b = Room.create!(name: "B", operator: @operator, location: @location)
    @type.assign_office_rooms!({ @a.id => 1, @b.id => 2 })
    @user = users(:cowork_tahoe_member)
    @other = users(:cowork_tahoe_non_member)
    @day = Date.current + 7
  end

  def office_pass!(day, user: @user)
    pass = DayPass.create!(user: user, billable: user, operator: @operator, location: @location,
                           day_pass_type: @type, day: day, imported: true)
    DayOffices::Allocator.allocate!(day_pass: pass)
    pass
  end

  # Books every pool room solid for the whole posted-hours span on `day`.
  # Mirrors DayOffices::AllocatorTest / Api::V1::DayPassesControllerTest.
  def fill_pool!(day)
    span = @location.posted_hours_span(day)
    [@a, @b].each { |r| Reservation.create!(user: @other, room: r, datetime_in: span.first, minutes: 600) }
  end

  test "moves the hold to the new date, releasing the old one" do
    pass = office_pass!(@day)
    old_hold = pass.office_hold
    target = @day + 1

    result = DayOffices::MoveHold.call(day_pass: pass, new_day: target)

    assert result.ok?
    assert_equal target, pass.reload.day
    assert Reservation.unscoped.find(old_hold.id).cancelled, "the old hold must be cancelled"
    new_hold = pass.reload_office_hold
    assert_equal result.hold.id, new_hold.id
    assert_not_equal old_hold.id, new_hold.id
    assert_equal target, new_hold.datetime_in.to_date
    assert_not new_hold.cancelled
  end

  test "a full target date rolls back the whole move: old hold stays live, pass day unchanged" do
    pass = office_pass!(@day)
    target = @day + 1
    fill_pool!(target)
    live_count_before = Reservation.where(room_id: [@a.id, @b.id]).count # old hold + 2 fillers = 3

    result = DayOffices::MoveHold.call(day_pass: pass, new_day: target)

    assert_not result.ok?
    assert_nil result.hold
    assert_equal @day, pass.reload.day
    assert pass.reload_office_hold.present?, "the original hold must still be live — its release must have rolled back with the rest of the transaction"
    assert_equal live_count_before, Reservation.where(room_id: [@a.id, @b.id]).count
  end

  test "a pass with no existing hold allocates fresh on the target date" do
    # Walk-in-no-office case (Task 11): the pass row exists but was never
    # allocated a room (e.g. sold out at purchase time and burned anyway).
    pass = DayPass.create!(user: @user, billable: @user, operator: @operator, location: @location,
                           day_pass_type: @type, day: @day, imported: true)
    assert_nil pass.office_hold, "sanity: pass starts with no hold"
    target = @day + 1

    result = DayOffices::MoveHold.call(day_pass: pass, new_day: target)

    assert result.ok?
    assert_equal target, pass.reload.day
    assert_equal target, result.hold.datetime_in.to_date
  end

  test "a pass with no existing hold refuses the move when the target date is also full" do
    # Design decision: a Day Office pass's move is office-conditional even
    # when there was nothing to release — moving to a full date must REFUSE,
    # not silently succeed with no office (that would strand the member on
    # the new date exactly like the sold-out case it looks identical to).
    pass = DayPass.create!(user: @user, billable: @user, operator: @operator, location: @location,
                           day_pass_type: @type, day: @day, imported: true)
    target = @day + 1
    fill_pool!(target)

    result = DayOffices::MoveHold.call(day_pass: pass, new_day: target)

    assert_not result.ok?
    assert_nil result.hold
    assert_equal @day, pass.reload.day
  end

  test "allocates the first-priority free room on the target date, not whatever the old room was" do
    span_original = @location.posted_hours_span(@day)
    # Room A (position 1) is busy on the ORIGINAL date only, so the original
    # allocation lands on B (the lower-priority room).
    Reservation.create!(user: @other, room: @a, datetime_in: span_original.first, minutes: 600)
    pass = office_pass!(@day)
    assert_equal @b, pass.office_hold.room, "sanity: original hold landed on the lower-priority room"

    target = @day + 1 # both rooms are free here

    result = DayOffices::MoveHold.call(day_pass: pass, new_day: target)

    assert result.ok?
    assert_equal @a, result.hold.room, "must re-evaluate priority fresh on the target date, not keep the old room"
  end
end
