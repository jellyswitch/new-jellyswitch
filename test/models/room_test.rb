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
end
