require "test_helper"

class Billing::Reservations::UpdateReservationDurationTest < ActiveSupport::TestCase
  def setup
    @reservation = reservations(:future_room_reservation)
    @room = @reservation.room
  end

  test "should update the reservation duration" do
    initial_duration = @reservation.minutes

    result = Billing::Reservations::UpdateReservationDuration.call(reservation: @reservation, additional_duration: 120)

    assert result.success?
    assert_equal @reservation.reload.minutes, initial_duration + 120
  end
end
