require "test_helper"

class CancelReservationTest < ActiveSupport::TestCase
  def setup
    @reservation = reservations(:future_room_reservation)
    @room = @reservation.room
  end

  test "should cancel free room reservations successfully" do
    @room.stubs(:paid_room?).returns(false)

    result = CancelReservation.call(reservation: @reservation)

    assert result.success?
    assert @reservation.reload.cancelled?
  end
end
