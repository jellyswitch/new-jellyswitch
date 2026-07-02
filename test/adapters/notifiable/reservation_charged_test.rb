require 'test_helper'

class Notifiable::ReservationChargedTest < ActiveSupport::TestCase
  setup do
    @reservation = reservations(:room_reservation)
    @reservation.update_column(:captured_amount_in_cents, 5000)
    @room = @reservation.room
  end

  test "message formats the captured amount" do
    n = Notifiable::ReservationCharged.new(@reservation)
    expected = "You were charged $50.00 for #{@room.name} on #{@reservation.datetime_in.strftime('%b %-d')}."
    assert_equal expected, n.send(:message)
  end

  test "recipients is the booker" do
    n = Notifiable::ReservationCharged.new(@reservation)
    assert_equal [@reservation.user], n.send(:recipients)
  end

  test "should_send_notification? is false when nothing was captured" do
    @reservation.update_column(:captured_amount_in_cents, 0)
    assert_not Notifiable::ReservationCharged.new(@reservation).send(:should_send_notification?)
  end

  test "deep link routes to the reservation" do
    data = Notifiable::ReservationCharged.new(@reservation).send(:deep_link_data)
    assert_equal "MyReservations", data[:screen]
    assert_equal @reservation.id, data[:resource_id]
  end
end
