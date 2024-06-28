require "test_helper"

class ReservationValidatorTest < ActiveSupport::TestCase
  def setup
    @user = users(:cowork_tahoe_member)
    @room = rooms(:small_meeting_room)

    @reservation_time = Time.zone.parse("2024-06-15 10:00:00")

    @reservation = Reservation.new(room: @room, datetime_in: @reservation_time, user: @user, minutes: 30)
  end

  test "should ignore for the cancelled reservation" do
    @reservation.cancelled = true

    assert @reservation.valid?
  end

  test "should add error if room is already booked for the selected time slot" do
    another_reservation = Reservation.create(room: @room, datetime_in: Time.zone.parse("2024-06-15 9:30:00"), user: @user, minutes: 45)

    assert_not @reservation.valid?
    assert_includes @reservation.errors[:base], "The requested time slot conflicts with an existing reservation. Please choose a different time or room."
  end

  test "should not add error if room is not booked for the selected time slot" do
    another_reservation = Reservation.create(room: @room, datetime_in: Time.zone.parse("2024-06-15 8:00:00"), user: @user, minutes: 60)

    assert @reservation.valid?
    assert_empty @reservation.errors[:base]
  end

  test "should add error if a reservation extend a meeting time overlapped with other reservation" do
    @reservation.save

    another_reservation = Reservation.create(room: @room, datetime_in: @reservation.datetime_out, user: @user, minutes: 30)

    @reservation.update(minutes: @reservation.minutes + 30)

    assert another_reservation.valid?
    assert_not @reservation.valid?
    assert_includes @reservation.errors[:base], "The requested time slot conflicts with an existing reservation. Please choose a different time or room."
  end
end
