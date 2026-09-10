require "test_helper"

# DayPassType#sold_out_message is the single wording for every "can't book
# this day" path. The empty-pool branch exists because a Day Office type
# with no rooms in its pool reported "fully booked" on every date — TLH's
# "Private Office Day Pass +1" did exactly that for a week.
class DayPassTypeSoldOutMessageTest < ActiveSupport::TestCase
  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @day = Date.new(2026, 9, 17)
    @office_type = DayPassType.create!(name: "Private Office Day Pass +1", operator: @operator,
                                       location: @location, kind: "day_office", amount_in_cents: 12500,
                                       included_meeting_room_minutes: 0)
  end

  test "office type with an empty pool says so instead of fully booked" do
    assert @office_type.office_pool_empty?
    msg = @office_type.sold_out_message(@day)

    assert_equal "Private Office Day Pass +1 can't be booked yet: no rooms are in its Day Office pool. " \
                 "Add rooms to it under Day Pass Types.", msg
    refute_includes msg, "fully booked"
  end

  test "office type with a room in the pool says fully booked" do
    room = Room.create!(name: "Office A", operator: @operator, location: @location)
    @office_type.assign_office_rooms!(room.id => 1)

    refute @office_type.office_pool_empty?
    assert_equal "Private Office Day Pass +1s are fully booked for September 17. Try another day.",
                 @office_type.sold_out_message(@day)
  end

  test "a pool of only archived rooms counts as empty (matches the allocator)" do
    room = Room.create!(name: "Office A", operator: @operator, location: @location)
    @office_type.assign_office_rooms!(room.id => 1)
    room.update!(archived: true)

    assert @office_type.office_pool_empty?
    assert_includes @office_type.sold_out_message(@day), "no rooms are in its Day Office pool"
  end

  test "standard types never claim an empty pool" do
    standard = DayPassType.create!(name: "Day Pass", operator: @operator, location: @location,
                                   kind: "standard", amount_in_cents: 2500, daily_limit: 2)

    refute standard.office_pool_empty?
    assert_equal "Day Passes are fully booked for September 17. Try another day.",
                 standard.sold_out_message(@day)
  end

  test "a pool room with capacity 0 is called out by name" do
    room = Room.create!(name: "Meeting Room", operator: @operator, location: @location, capacity: 0)
    @office_type.assign_office_rooms!(room.id => 1)

    refute @office_type.office_pool_empty?
    assert_equal "Private Office Day Pass +1 can't be booked yet: Meeting Room has a capacity of 0. " \
                 "Set the capacity under Rooms.", @office_type.sold_out_message(@day)
  end

  test "date_text overrides the default date wording (web short_date idiom)" do
    room = Room.create!(name: "Office A", operator: @operator, location: @location)
    @office_type.assign_office_rooms!(room.id => 1)

    assert_includes @office_type.sold_out_message(@day, date_text: "Thu 9/17"), "fully booked for Thu 9/17"
  end
end
