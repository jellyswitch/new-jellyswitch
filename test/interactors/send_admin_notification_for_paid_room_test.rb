require 'test_helper'

class SendAdminNotificationForPaidRoomTest < ActiveSupport::TestCase
  def setup
    @reservation = reservations(:room_reservation)
    @interactor = SendAdminNotificationForPaidRoom.new(reservation: @reservation)
  end

  test "calls SendNotificationsJob if room is a paid room" do
    @reservation.room.stubs(:paid_room?).returns(true)
    SendNotificationsJob.expects(:perform_later).with(@reservation, 'PaidRoomReservation')

    @interactor.call
  end

  test "does not call SendNotificationsJob if room is not a paid room" do
    @reservation.room.stubs(:paid_room?).returns(false)
    SendNotificationsJob.expects(:perform_later).never

    @interactor.call
  end
end
