require 'test_helper'

class Notifiable::ReservationReminderTest < ActiveSupport::TestCase
  setup do
    @reservation = reservations(:room_reservation)
    @room = @reservation.room
  end

  # Phase 6 / ADR 0013: the booker reminder is the access-window "come back" push.
  test "paid booking: says the building is open and to wait for the room" do
    @reservation.paid = true
    msg = Notifiable::ReservationReminder.new(@reservation).send(:message)
    assert_includes msg, "You now have access to #{@room.location.name}."
    assert_includes msg, "Your #{@room.name} booking starts at"
    assert_match(/Please wait until then to use the room, since it may be in use\./, msg)
  end

  test "unpaid booking (day pass/member): room start time only, no access line" do
    @reservation.paid = false
    msg = Notifiable::ReservationReminder.new(@reservation).send(:message)
    assert msg.start_with?("Your #{@room.name} booking starts at"), msg
    assert_match(/Please wait until then to use the room, since it may be in use\./, msg)
    assert_no_match(/access/i, msg)
  end

  test "recipients is the booker" do
    n = Notifiable::ReservationReminder.new(@reservation)
    assert_equal [@reservation.user], n.send(:recipients)
  end
end
