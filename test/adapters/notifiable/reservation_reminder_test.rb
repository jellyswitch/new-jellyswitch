require 'test_helper'

class Notifiable::ReservationReminderTest < ActiveSupport::TestCase
  setup do
    @reservation = reservations(:room_reservation)
    @room = @reservation.room
  end

  # Phase 6 / ADR 0013: the booker reminder is the access-window "come back" push.
  test "message says the building is open, not the room" do
    msg = Notifiable::ReservationReminder.new(@reservation).send(:message)
    assert_match(/building is open/i, msg)
    assert_match(/wait until then to use the room/i, msg)
    assert_includes msg, @room.name
    assert_no_match(/get into/i, msg)
  end

  test "recipients is the booker" do
    n = Notifiable::ReservationReminder.new(@reservation)
    assert_equal [@reservation.user], n.send(:recipients)
  end
end
