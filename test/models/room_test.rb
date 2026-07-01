require "test_helper"

class RoomTest < ActiveSupport::TestCase
  setup do
    @room = rooms(:small_meeting_room)
    @room.reservations.delete_all
    @user = users(:cowork_tahoe_member)
    @start = 2.days.from_now.change(hour: 10, min: 0)
  end

  test "available? reports a booked slot as unavailable" do
    Reservation.create!(user: @user, room: @room, datetime_in: @start, minutes: 60)

    refute @room.available?(start_time: @start, duration: 60)
  end

  test "available? with except: ignores the excluded reservation" do
    res = Reservation.create!(user: @user, room: @room, datetime_in: @start, minutes: 60)

    assert @room.available?(start_time: @start, duration: 60, except: res.id),
      "the reservation being edited should not block its own slot"
  end

  test "available? with except: still sees other reservations" do
    res   = Reservation.create!(user: @user, room: @room, datetime_in: @start, minutes: 60)
    other = Reservation.create!(user: @user, room: @room, datetime_in: @start + 60.minutes, minutes: 60)

    refute @room.available?(start_time: other.datetime_in, duration: 60, except: res.id)
  end

  # ADR 0019: the no-coverage room list must widen from cash-rentable-only to
  # also include day-pass-unlockable rooms, so the buy-a-day-pass confirm can
  # surface instead of the included room being hidden.
  test "rentable_or_day_pass_included lists cash-rentable and included rooms, excludes member-only" do
    op  = operators(:cowork_tahoe)
    loc = locations(:cowork_tahoe_location)
    ActsAsTenant.with_tenant(op) do
      cash     = create(:room, operator: op, location: loc, rentable: true,  hourly_rate_in_cents: 5000, include_with_day_pass: false)
      included = create(:room, operator: op, location: loc, rentable: false, hourly_rate_in_cents: 0,    include_with_day_pass: true)
      member   = create(:room, operator: op, location: loc, rentable: false, hourly_rate_in_cents: 0,    include_with_day_pass: false)

      ids = loc.rooms.rentable_or_day_pass_included.pluck(:id)
      assert_includes ids, cash.id,     "cash-rentable room should be listed"
      assert_includes ids, included.id, "included (day-pass-unlockable) room should be listed"
      refute_includes ids, member.id,   "member-only room should stay hidden from no-coverage users"
    end
  end
end
