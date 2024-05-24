require 'test_helper'

class Notifiable::ReservationTest < ActiveSupport::TestCase
  def setup
    @reservation = reservations(:room_reservation)
    @user = @reservation.user
    @operator = @user.operator
    @room = @reservation.room
  end

  test "create_feed_item creates a feed item with correct attributes" do
    notifiable = Notifiable::Reservation.new(@reservation)
    FeedItemCreator.expects(:create_feed_item).with(@operator, @user, type: "reservation", reservation_id: @reservation.id)

    notifiable.send(:create_feed_item)
  end

  test "should_send_notification? returns true when operator has reservation_notifications enabled" do
    @operator.update reservation_notifications: true
    notifiable = Notifiable::Reservation.new(@reservation)

    assert notifiable.send(:should_send_notification?)
  end

  test "should_send_notification? returns false when operator does not have reservation_notifications enabled" do
    @operator.update reservation_notifications: false
    notifiable = Notifiable::Reservation.new(@reservation)

    assert_not notifiable.send(:should_send_notification?)
  end

  test "message returns the correct notification message" do
    notifiable = Notifiable::Reservation.new(@reservation)
    expected_message = "#{@user.name} has reserved #{@room.name}"

    assert_equal expected_message, notifiable.send(:message)
  end

  test "recipients returns the correct recipients" do
    notifiable = Notifiable::Reservation.new(@reservation)

    assert_equal @operator.users.admins, notifiable.send(:recipients)
  end
end
