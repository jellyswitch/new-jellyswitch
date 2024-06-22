require "test_helper"

class ReservationTest < ActiveSupport::TestCase
  def setup
    @ongoing_reservation = reservations(:room_reservation)
    @ongoing_reservation.update(datetime_in: Time.zone.now)

    @future_reservation = reservations(:future_room_reservation)
  end

  def teardown
    @future_reservation.destroy
    @ongoing_reservation.destroy
  end

  test "ongoing scope should return ongoing reservations" do
    ongoing_reservations = Reservation.ongoing

    assert_includes ongoing_reservations, @ongoing_reservation
    assert_not_includes ongoing_reservations, @future_reservation
  end

  test "datetime_out should return the datetime_in plus the minutes" do
    expected_datetime_out = @ongoing_reservation.datetime_in + @ongoing_reservation.minutes.minutes

    assert_equal @ongoing_reservation.datetime_out, expected_datetime_out
  end
end
