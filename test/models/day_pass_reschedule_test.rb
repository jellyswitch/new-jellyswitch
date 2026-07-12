require "test_helper"

class DayPassRescheduleTest < ActiveSupport::TestCase
  setup do
    @location = locations(:cowork_tahoe_location)
    @member = users(:cowork_tahoe_member)
    @pass = day_passes(:cowork_tahoe_day_pass)
    @pass.update_columns(location_id: @location.id, day: Date.new(2026, 7, 1))
    @tz = ActiveSupport::TimeZone[@location.time_zone]
  end

  test "a pass with no entry on its day is unused and reschedulable" do
    refute @pass.used?
    assert @pass.reschedulable?
  end

  test "a check-in on the pass day marks it used" do
    Checkin.create!(user: @member, billable: @member, location: @location,
                    datetime_in: @tz.local(2026, 7, 1, 10, 0))

    assert @pass.used?
    refute @pass.reschedulable?
  end

  test "a door punch on the pass day marks it used" do
    door = Door.create!(name: "Front", slug: "front-#{SecureRandom.hex(4)}",
                        location: @location, operator: @pass.operator,
                        kisi_id: 999, available: true)
    DoorPunch.create!(user: @member, door: door, operator: @pass.operator,
                      created_at: @tz.local(2026, 7, 1, 9, 0))

    assert @pass.used?
  end

  test "entries on other days do not lock the pass" do
    Checkin.create!(user: @member, billable: @member, location: @location,
                    datetime_in: @tz.local(2026, 6, 30, 10, 0))

    assert @pass.reschedulable?
  end
end
