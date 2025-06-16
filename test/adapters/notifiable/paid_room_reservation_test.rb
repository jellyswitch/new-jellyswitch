require 'test_helper'

class Notifiable::PaidRoomReservationTest < ActiveSupport::TestCase
  def setup
    @reservation = reservations(:room_reservation)
    @location = locations(:cowork_tahoe_location)
    @user = @reservation.user
    @operator = @user.operator
    @room = @reservation.room
  end

  test "should_send_notification? returns true if room is a paid room" do
    @room.stubs(:paid_room?).returns(true)
    notifiable = Notifiable::PaidRoomReservation.new(@reservation)

    assert notifiable.send(:should_send_notification?)
  end

  test "should_send_notification? returns false if room is not a paid room" do
    @room.stubs(:paid_room?).returns(false)
    notifiable = Notifiable::PaidRoomReservation.new(@reservation)

    assert_not notifiable.send(:should_send_notification?)
  end

  test "message returns the correct notification message" do
    notifiable = Notifiable::PaidRoomReservation.new(@reservation)
    expected_message = "#{@user.name} has booked a paid meeting room"

    assert_equal expected_message, notifiable.send(:message)
  end

  test "recipients returns the correct recipients" do
    notifiable = Notifiable::PaidRoomReservation.new(@reservation)

    assert_equal @operator.users.relevant_admins_of_location(@location), notifiable.send(:recipients)
  end
end
