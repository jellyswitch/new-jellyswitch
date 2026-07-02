require 'test_helper'

class Notifiable::ReservationReminderTest < ActiveSupport::TestCase
  setup do
    @reservation = reservations(:room_reservation)
    @room = @reservation.room
  end

  # Phase 6 / ADR 0013: the booker reminder is the access-window "come back" push.
  test "message tells the booker they can get in now" do
    msg = Notifiable::ReservationReminder.new(@reservation).send(:message)
    assert_match(/get into/i, msg)
    assert_includes msg, @room.name
  end

  test "recipients is the booker" do
    n = Notifiable::ReservationReminder.new(@reservation)
    assert_equal [@reservation.user], n.send(:recipients)
  end
end
