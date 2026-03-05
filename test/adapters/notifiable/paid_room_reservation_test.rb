require 'test_helper'

class Notifiable::PaidRoomReservationTest < ActiveSupport::TestCase
  def setup
    @reservation = reservations(:room_reservation)
    @location = locations(:cowork_tahoe_location)
    @user = @reservation.user
    @operator = @user.operator
    @room = @reservation.room
  end

  test "create_feed_item creates a feed item with correct attributes" do
    notifiable = Notifiable::PaidRoomReservation.new(@reservation)
    FeedItemCreator.expects(:create_feed_item).with(@operator, @location, @user, type: "paid-room-reservation", reservation_id: @reservation.id)

    notifiable.send(:create_feed_item)
  end

  test "deep_link_data returns correct type and path" do
    notifiable = Notifiable::PaidRoomReservation.new(@reservation)
    data = notifiable.send(:deep_link_data)

    assert_equal "reservation", data[:type]
    assert_equal @reservation.id, data[:resource_id]
    assert_equal "/reservations/#{@reservation.id}", data[:path]
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
