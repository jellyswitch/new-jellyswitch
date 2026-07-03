require "test_helper"

class DoorRoomLockTest < ActiveSupport::TestCase
  test "a door attached to a room is that room's lock" do
    # No doors fixture file exists — build one the way controller tests do.
    door = Door.create!(name: "Front Door", operator: operators(:cowork_tahoe),
                        location: locations(:cowork_tahoe_location), available: true)
    refute door.room_lock?, "unattached door is a Building Door"

    door.update!(room: rooms(:small_meeting_room))
    assert door.room_lock?
    assert_includes rooms(:small_meeting_room).doors, door
  end
end
