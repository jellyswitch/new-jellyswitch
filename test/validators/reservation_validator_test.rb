require "test_helper"

class ReservationValidatorTest < ActiveSupport::TestCase
  setup do
    @room = rooms(:small_meeting_room)
    @user = users(:cowork_tahoe_member)
    @zone = ActiveSupport::TimeZone[@room.location.time_zone]
    @room.reservations.delete_all
    day = Date.current + 7
    @start = @zone.local(day.year, day.month, day.day, 10)
    Reservation.create!(user: @user, room: @room, datetime_in: @start, minutes: 60)
  end

  test "overlap message names the room and the requested window" do
    clash = Reservation.new(user: @user, room: @room, datetime_in: @start, minutes: 60)
    refute clash.valid?
    assert_equal "#{@room.name} is no longer free 10:00–11:00 AM.",
      clash.errors.full_messages.first
  end

  test "overlap error is tagged :overlap in details" do
    clash = Reservation.new(user: @user, room: @room, datetime_in: @start, minutes: 30)
    clash.valid?
    assert clash.errors.details[:base].any? { |d| d[:error] == :overlap }
  end

  test "non-overlapping reservation stays valid" do
    free = Reservation.new(user: @user, room: @room,
      datetime_in: @start + 2.hours, minutes: 60)
    assert free.valid?
  end

  test "cancelled reservation skips the overlap check" do
    clash = Reservation.new(user: @user, room: @room, datetime_in: @start, minutes: 60)
    clash.cancelled = true
    assert clash.valid?
  end

  test "extending a meeting into another reservation adds the overlap error" do
    mine = Reservation.create!(user: @user, room: @room,
      datetime_in: @start + 2.hours, minutes: 30)
    Reservation.create!(user: @user, room: @room,
      datetime_in: mine.datetime_out, minutes: 30)

    mine.minutes += 30
    assert_not mine.valid?
    assert_includes mine.errors[:base],
      "#{@room.name} is no longer free #{mine.window_label}."
  end
end
