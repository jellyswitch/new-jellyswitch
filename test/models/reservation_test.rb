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

  test "should return true for ongoing reservation" do
    assert @ongoing_reservation.ongoing?
  end

  test "should return true for future reservation" do
    assert @future_reservation.future?
  end

  test "end_now! updates the minutes to the actual duration" do
    new_duration = 12 # minutes

    Timecop.freeze(@ongoing_reservation.datetime_in + new_duration.minutes) do
      @ongoing_reservation.end_now!
      assert_equal @ongoing_reservation.reload.minutes, new_duration
      assert @ongoing_reservation.ended_early?
    end
  end

  test "end_now! does not change minutes if called after the original end time" do
    original_duration = @ongoing_reservation.minutes
    new_duration = original_duration + 5.minutes # minutes

    Timecop.freeze(@ongoing_reservation.datetime_in + new_duration.minutes) do
      @ongoing_reservation.end_now!
      assert_not_equal @ongoing_reservation.reload.minutes, new_duration
      assert_equal @ongoing_reservation.minutes, original_duration
      assert @ongoing_reservation.ended_early?
    end
  end
end
