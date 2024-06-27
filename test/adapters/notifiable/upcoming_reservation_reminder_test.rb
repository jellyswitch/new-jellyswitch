require "test_helper"

class Notifiable::UpcomingReservationReminderTest < ActiveSupport::TestCase
  def setup
    @reservation = reservations(:room_reservation)
    @user = @reservation.user
    @room = @reservation.room
  end

  test "create_feed_item does not create a feed item" do
    notifiable = Notifiable::UpcomingReservationReminder.new(@reservation)
    FeedItemCreator.expects(:create_feed_item).never

    notifiable.send(:create_feed_item)
  end

  test "should_send_notification? always returns true" do
    notifiable = Notifiable::UpcomingReservationReminder.new(@reservation)

    assert notifiable.send(:should_send_notification?)
  end

  test "message returns the correct notification message" do
    notifiable = Notifiable::UpcomingReservationReminder.new(@reservation)
    expected_message = "Another party has reserved #{@room.name}, please prepare to wrap up your meeting."

    assert_equal expected_message, notifiable.send(:message)
  end

  test "recipients returns only the user of the reservation" do
    notifiable = Notifiable::UpcomingReservationReminder.new(@reservation)

    assert_equal [@user], notifiable.send(:recipients)
  end
end
