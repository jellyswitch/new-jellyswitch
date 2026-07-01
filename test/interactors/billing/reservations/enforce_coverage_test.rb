require "test_helper"

class Billing::Reservations::EnforceCoverageTest < ActiveSupport::TestCase
  setup { @operator = operators(:cowork_tahoe); @location = locations(:cowork_tahoe_location) }

  test "fails when an included booking has no coverage committed" do
    ActsAsTenant.with_tenant(@operator) do
      user = create(:user, operator: @operator, original_location: @location, current_location: @location)
      room = create(:room, operator: @operator, location: @location, hourly_rate_in_cents: 0, include_with_day_pass: true)
      res  = create(:reservation, user: user, room: room, minutes: 60, datetime_in: (Date.current + 3).to_time + 9.hours)
      result = Billing::Reservations::EnforceCoverage.call(reservation: res, user: user, location: @location, enforce_coverage: true)
      assert result.failure?
      assert_match(/day pass/i, result.message)
    end
  end

  test "passes for a paid room" do
    ActsAsTenant.with_tenant(@operator) do
      user = create(:user, operator: @operator, original_location: @location, current_location: @location)
      room = create(:room, operator: @operator, location: @location, hourly_rate_in_cents: 5000, include_with_day_pass: false)
      res  = create(:reservation, user: user, room: room, minutes: 60, datetime_in: (Date.current + 3).to_time + 9.hours)
      result = Billing::Reservations::EnforceCoverage.call(reservation: res, user: user, location: @location, enforce_coverage: true)
      assert result.success?
    end
  end

  test "passes once a pass covers the date" do
    ActsAsTenant.with_tenant(@operator) do
      user = create(:user, operator: @operator, original_location: @location, current_location: @location)
      room = create(:room, operator: @operator, location: @location, hourly_rate_in_cents: 0, include_with_day_pass: true)
      dpt  = create(:day_pass_type, operator: @operator, location: @location, included_meeting_room_minutes: 60)
      create(:day_pass, user: user, billable: user, operator: @operator, location: @location, day_pass_type: dpt, day: Date.current + 3)
      res  = create(:reservation, user: user, room: room, minutes: 60, datetime_in: (Date.current + 3).to_time + 9.hours)
      result = Billing::Reservations::EnforceCoverage.call(reservation: res, user: user, location: @location, enforce_coverage: true)
      assert result.success?
    end
  end
end
