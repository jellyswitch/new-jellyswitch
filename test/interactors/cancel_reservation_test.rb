require "test_helper"

class CancelReservationTest < ActiveSupport::TestCase
  def setup
    @reservation = reservations(:future_room_reservation)
    @room = @reservation.room
  end

  test "members can cancel free room reservations successfully" do
    @room.stubs(:paid_room?).returns(false)
    @user = users(:cowork_tahoe_member)

    result = CancelReservation.call(reservation: @reservation, current_user: @user)

    assert result.success?
    assert @reservation.reload.cancelled?
  end

  test "members not able to cancel paid room reservations" do
    @room.stubs(:paid_room?).returns(true)
    @user = users(:cowork_tahoe_member)

    result = CancelReservation.call(reservation: @reservation, current_user: @user)

    assert_not result.success?
    assert_equal result.message, "You are not allowed to cancel this reservation since this is a paid room, please contact the workspace admin for assistance."
    assert_not @reservation.reload.cancelled?
  end

  test "admin should cancel paid room reservation successfully" do
    @room.stubs(:paid_room?).returns(true)
    @admin = users(:cowork_tahoe_admin)

    context = CancelReservation.call(reservation: @reservation, current_user: @admin)
    assert context.success?
    assert @reservation.reload.cancelled
  end
end
