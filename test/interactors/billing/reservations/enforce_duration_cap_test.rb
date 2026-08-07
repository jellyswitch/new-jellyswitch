require "test_helper"

# Duration backstop (prod audit 2026-08-07): member self-serve bookings can't
# exceed the room's bookable cap (free rooms 4h, priced rooms 12h; staff keep
# the 12h admin allowance). Flows that don't opt in via enforce_duration_cap —
# the staff calendar / on-behalf bookings, where context.user is the booked
# member rather than the booker — are untouched.
class Billing::Reservations::EnforceDurationCapTest < ActiveSupport::TestCase
  setup { @operator = operators(:cowork_tahoe); @location = locations(:cowork_tahoe_location) }

  def call_step(minutes:, rate_cents: 0, user: nil, enforce: true)
    ActsAsTenant.with_tenant(@operator) do
      user ||= create(:user, operator: @operator, original_location: @location, current_location: @location)
      room = create(:room, operator: @operator, location: @location, hourly_rate_in_cents: rate_cents)
      args = {
        reservation_params: { datetime_in: Time.current, minutes: minutes, room: room },
        user: user,
        location: @location,
      }
      args[:enforce_duration_cap] = true if enforce
      Billing::Reservations::EnforceDurationCap.call(**args)
    end
  end

  test "blocks a member booking a free room past 4 hours" do
    result = call_step(minutes: 300)
    assert result.failure?
    assert_match(/can be booked for up to 4 hours/, result.message)
  end

  test "allows exactly 4 hours on a free room" do
    assert call_step(minutes: 240).success?
  end

  test "allows a member 12 hours on a priced room" do
    assert call_step(minutes: 720, rate_cents: 2500).success?
  end

  test "blocks a member past 12 hours on a priced room" do
    result = call_step(minutes: 750, rate_cents: 2500)
    assert result.failure?
    assert_match(/can be booked for up to 12 hours/, result.message)
  end

  test "staff booking themselves keep the 12h admin allowance" do
    user = ActsAsTenant.with_tenant(@operator) do
      create(:user, operator: @operator, superadmin: true, original_location: @location, current_location: @location)
    end
    assert call_step(minutes: 300, user: user).success?
  end

  test "no-op when enforce_duration_cap is not set (staff calendar / on-behalf flows)" do
    assert call_step(minutes: 300, enforce: false).success?
  end
end
