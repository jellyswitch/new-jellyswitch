require "test_helper"

class DayPassTypeRoomTest < ActiveSupport::TestCase
  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @type = DayPassType.create!(name: "Day Office", operator: @operator,
                                location: @location, amount_in_cents: 7500, kind: "day_office")
    @room = Room.create!(name: "Office 1", operator: @operator, location: @location)
  end

  test "requires position and unique room per type" do
    DayPassTypeRoom.create!(day_pass_type: @type, room: @room, position: 1)
    dup = DayPassTypeRoom.new(day_pass_type: @type, room: @room, position: 2)
    assert_not dup.valid?
    assert dup.errors[:room_id].present?
  end

  test "rejects a room from another location" do
    other_location = Location.create!(operator: @operator, name: "Other Location")
    other = Room.create!(name: "Elsewhere", operator: @operator, location: other_location)
    row = DayPassTypeRoom.new(day_pass_type: @type, room: other, position: 1)
    assert_not row.valid?
    assert_match(/location/i, row.errors.full_messages.join)
  end

  # Deleting a room should shrink the pool, not raise an FK-violation 500.
  test "destroying a room removes it from the pool without breaking the type" do
    row = DayPassTypeRoom.create!(day_pass_type: @type, room: @room, position: 1)

    @room.destroy

    assert_not DayPassTypeRoom.exists?(row.id)
    assert @type.reload.valid?
  end
end
