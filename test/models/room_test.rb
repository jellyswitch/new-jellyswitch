require "test_helper"

class RoomTest < ActiveSupport::TestCase
  test "paid_room? returns true when hourly_rate_in_cents is greater than 0 and room is rentable" do
    room = Room.new(hourly_rate_in_cents: 100, rentable: true)
    assert room.paid_room?
  end

  test "paid_room? returns false when hourly_rate_in_cents is 0 and room is rentable" do
    room = Room.new(hourly_rate_in_cents: 0, rentable: true)
    assert_not room.paid_room?
  end

  test "paid_room? returns false when hourly_rate_in_cents is 0 and room is not rentable" do
    room = Room.new(hourly_rate_in_cents: 100, rentable: false)
    assert_not room.paid_room?
  end
end
