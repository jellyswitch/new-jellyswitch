require 'test_helper'

class RoomTest < ActiveSupport::TestCase
  test 'paid_room? returns true when hourly_rate_in_cents is greater than 0' do
    room = Room.new(hourly_rate_in_cents: 100)
    assert room.paid_room?
  end

  test 'paid_room? returns false when hourly_rate_in_cents is negative' do
    room = Room.new(hourly_rate_in_cents: -100)
    assert_not room.paid_room?
  end
end
