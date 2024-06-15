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

  def teardown
    Timecop.return
  end

  test "self.unavailable should return unavailable rooms for give date, time and duration" do
    now = Time.zone.parse("2024-06-15 10:00:00")
    Timecop.freeze(now)

    user = users(:cowork_tahoe_member)

    unavailable_room = rooms(:small_meeting_room)
    reservation = Reservation.create(room: unavailable_room, datetime_in: now.change(hour: 15), user: user, minutes: 30)

    assert_includes Room.unavailable(date: Time.zone.today, time: 14, duration: 120), unavailable_room
  end

  test "self.available should return available rooms for give date, time and duration" do
    now = Time.zone.parse("2024-06-15 10:00:00")
    Timecop.freeze(now)

    user = users(:cowork_tahoe_member)

    free_room = rooms(:small_meeting_room)
    free_room.reservations.destroy_all # Ensure room is free

    assert_includes Room.available, free_room
  end
end
