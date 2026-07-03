require 'test_helper'

class Notifiable::ReservationStartedTest < ActiveSupport::TestCase
  setup do
    @reservation = reservations(:room_reservation)
    @room = @reservation.room
  end

  test "message names the room" do
    n = Notifiable::ReservationStarted.new(@reservation)
    assert_equal "Your #{@room.name} booking has started.", n.send(:message)
  end

  test "recipients is the booker" do
    n = Notifiable::ReservationStarted.new(@reservation)
    assert_equal [@reservation.user], n.send(:recipients)
  end
end
