require "test_helper"

# Room Entries are not building entries (ADR 0021): opening a Room Lock never
# burns a Day Pool day — only Building Door punches do.
class DayPoolRoomEntryTest < ActiveSupport::TestCase
  test "room entries never count against the Day Pool" do
    member = users(:cowork_tahoe_member)
    sub = member.subscriptions.detect(&:active?)
    skip "fixture member has no active subscription" unless sub
    sub.plan.update!(has_day_limit: true, day_limit: 10)

    room = rooms(:small_meeting_room)
    lock = Door.create!(name: "Lock", operator: sub.plan.operator,
                        location: sub.plan.location, room: room, available: true)
    front = Door.create!(name: "Front", operator: sub.plan.operator,
                         location: sub.plan.location, available: true)

    used_before = sub.day_pool_used
    DoorPunch.create!(user: member, door: lock, operator: sub.plan.operator, room_entry: true)
    assert_equal used_before, sub.reload.day_pool_used, "room entry burned a Day Pool day"

    DoorPunch.create!(user: member, door: front, operator: sub.plan.operator)
    assert_equal used_before + 1, sub.reload.day_pool_used
  end

  test "a room entry alone does not mark today as a used day" do
    member = users(:cowork_tahoe_member)
    sub = member.subscriptions.detect(&:active?)
    skip "fixture member has no active subscription" unless sub
    sub.plan.update!(has_day_limit: true, day_limit: 10)

    room = rooms(:small_meeting_room)
    lock = Door.create!(name: "Lock", operator: sub.plan.operator,
                        location: sub.plan.location, room: room, available: true)

    DoorPunch.create!(user: member, door: lock, operator: sub.plan.operator, room_entry: true)
    refute sub.used_day_today?, "room entry counted as building entry for today"
  end

  test "usage report door-punch days exclude room entries" do
    member = users(:cowork_tahoe_member)
    room = rooms(:small_meeting_room)
    operator = operators(:cowork_tahoe)
    location = locations(:cowork_tahoe_location)
    lock = Door.create!(name: "Lock", operator: operator, location: location,
                        room: room, available: true)

    DoorPunch.create!(user: member, door: lock, operator: operator, room_entry: true)
    report = Jellyswitch::UsageReport.new(member)
    assert_empty report.door_punches, "room entry showed up as an entry day in UsageReport"
  end
end
