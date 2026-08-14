require "test_helper"

# A metered day pass's included-minutes cap is only ever enforced as money
# (overage cents at the location rate). At a location with NO overage rate the
# cap was fiction: over-allowance bookings priced to $0 and sailed through with
# no card on file (Eda / Untethered Fulton, 2026-08-14 — 3.5h on a free pass).
# This guard blocks that booking instead. Everywhere a rate exists, billing
# stays the enforcement and the guard stays out of the way.
class Billing::Reservations::EnforceMeteredRoomLimitTest < ActiveSupport::TestCase
  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @location.update!(overage_rate_in_cents: 0)
  end

  def build_booking(minutes:, included: 120, rate: 0, day_pass: true, room_rate: 0)
    user = create(:user, operator: @operator, original_location: @location, current_location: @location)
    room = create(:room, operator: @operator, location: @location,
                         hourly_rate_in_cents: room_rate, include_with_day_pass: room_rate.zero?)
    @location.update!(overage_rate_in_cents: rate)
    if day_pass
      dpt = create(:day_pass_type, operator: @operator, location: @location,
                                   included_meeting_room_minutes: included)
      create(:day_pass, user: user, billable: user, operator: @operator, location: @location,
                        day_pass_type: dpt, day: Date.current + 3)
    end
    res = create(:reservation, user: user, room: room, minutes: minutes,
                               datetime_in: (Date.current + 3).to_time + 9.hours)
    [user, room, res]
  end

  test "blocks an over-allowance booking where the location has no overage rate (Eda regression)" do
    ActsAsTenant.with_tenant(@operator) do
      user, _room, res = build_booking(minutes: 209, included: 120)
      result = Billing::Reservations::EnforceMeteredRoomLimit.call(
        reservation: res, user: user, location: @location, enforce_coverage: true)
      assert result.failure?
      assert_match(/120 minutes/, result.message)
      assert_match(/89 minutes over/, result.message)
    end
  end

  test "allows a booking within the allowance" do
    ActsAsTenant.with_tenant(@operator) do
      user, _room, res = build_booking(minutes: 60, included: 120)
      result = Billing::Reservations::EnforceMeteredRoomLimit.call(
        reservation: res, user: user, location: @location, enforce_coverage: true)
      assert result.success?
    end
  end

  test "stays out of the way where the location HAS an overage rate (billing enforces there)" do
    ActsAsTenant.with_tenant(@operator) do
      user, _room, res = build_booking(minutes: 209, included: 120, rate: 1500)
      result = Billing::Reservations::EnforceMeteredRoomLimit.call(
        reservation: res, user: user, location: @location, enforce_coverage: true)
      assert result.success?
    end
  end

  test "no-op without enforce_coverage (staff / admin on-behalf keeps booking uncapped)" do
    ActsAsTenant.with_tenant(@operator) do
      user, _room, res = build_booking(minutes: 209, included: 120)
      result = Billing::Reservations::EnforceMeteredRoomLimit.call(
        reservation: res, user: user, location: @location)
      assert result.success?
    end
  end

  test "no-op for an unmetered pass (no included_meeting_room_minutes configured)" do
    ActsAsTenant.with_tenant(@operator) do
      user, _room, res = build_booking(minutes: 209, included: nil)
      result = Billing::Reservations::EnforceMeteredRoomLimit.call(
        reservation: res, user: user, location: @location, enforce_coverage: true)
      assert result.success?
    end
  end

  test "no-op for a priced room (bills its own hourly rate)" do
    ActsAsTenant.with_tenant(@operator) do
      user, _room, res = build_booking(minutes: 209, included: 120, room_rate: 5000)
      result = Billing::Reservations::EnforceMeteredRoomLimit.call(
        reservation: res, user: user, location: @location, enforce_coverage: true)
      assert result.success?
    end
  end

  test "counts the member's other included bookings that day against the allowance" do
    ActsAsTenant.with_tenant(@operator) do
      user, room, res = build_booking(minutes: 60, included: 120)
      create(:reservation, user: user, room: room, minutes: 90,
                           datetime_in: (Date.current + 3).to_time + 13.hours)
      result = Billing::Reservations::EnforceMeteredRoomLimit.call(
        reservation: res, user: user, location: @location, enforce_coverage: true)
      assert result.failure?
      assert_match(/30 minutes over/, result.message)
    end
  end
end