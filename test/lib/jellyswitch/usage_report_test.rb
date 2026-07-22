require "test_helper"

# Check-ins stopped being recorded in Feb 2023 (the day-pass organizers that
# created them lost their callers), so member usage must be derivable from
# what IS collected: door punches, reservations, and day passes. Day passes
# previously never counted toward days_used, so a walk-in who bought passes
# all month showed zero usage.
class UsageReportTest < ActiveSupport::TestCase
  setup do
    @member   = users(:cowork_tahoe_member)
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)

    # Exact-count assertions below; the member fixture carries dynamic-dated
    # activity (checkins/reservations "today"), so start from a clean slate.
    @member.checkins.destroy_all
    @member.door_punches.destroy_all
    @member.reservations.destroy_all
    @member.day_passes.destroy_all
  end

  test "a day-pass-only day counts as a used day" do
    DayPass.create!(
      user: @member,
      billable: @member,
      operator: @operator,
      location: @location,
      day_pass_type: day_pass_type(:cowork_tahoe_day_pass_type),
      day: Date.current,
    )

    report = Jellyswitch::UsageReport.new(@member)
    assert_includes report.day_passes.keys, Date.current
    assert_includes report.days_used.keys, Date.current
    assert_equal 1, report.days_used_count
  end

  test "a building door punch counts as a used day" do
    door = Door.create!(name: "Front", operator: @operator,
                        location: @location, available: true)
    DoorPunch.create!(user: @member, door: door, operator: @operator)

    report = Jellyswitch::UsageReport.new(@member)
    assert_includes report.days_used.keys, Date.current
  end

  test "one visit reachable three ways still counts one day" do
    door = Door.create!(name: "Front", operator: @operator,
                        location: @location, available: true)
    DoorPunch.create!(user: @member, door: door, operator: @operator)
    DayPass.create!(
      user: @member,
      billable: @member,
      operator: @operator,
      location: @location,
      day_pass_type: day_pass_type(:cowork_tahoe_day_pass_type),
      day: Date.current,
    )

    report = Jellyswitch::UsageReport.new(@member)
    assert_equal 1, report.days_used_count
  end
end
