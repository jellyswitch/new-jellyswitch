require "test_helper"

# Business-hours rule (Nash incident, 2026-08-07): member self-service bookings
# must start AND end inside the location's posted hours. Members, leaseholders,
# superadmins, and location staff are exempt (they book 24/7); flows that don't
# opt in via enforce_posted_hours — admin on-behalf bookings — are untouched.
class Billing::Reservations::EnforcePostedHoursTest < ActiveSupport::TestCase
  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @location.update!(time_zone: "Pacific Time (US & Canada)",
                      working_day_start: "06:00", working_day_end: "20:00",
                      open_saturday: false, open_sunday: false)
    @zone = ActiveSupport::TimeZone["Pacific Time (US & Canada)"]
    @tuesday  = Date.current.next_occurring(:tuesday) + 7
    @saturday = Date.current.next_occurring(:saturday) + 7
  end

  def call_step(datetime_in:, minutes: 60, user: nil, enforce: true)
    ActsAsTenant.with_tenant(@operator) do
      user ||= create(:user, operator: @operator, original_location: @location, current_location: @location)
      room = create(:room, operator: @operator, location: @location,
                    hourly_rate_in_cents: 0, include_with_day_pass: true)
      args = {
        reservation_params: { datetime_in: datetime_in, minutes: minutes, room: room },
        user: user,
        location: @location,
      }
      args[:enforce_posted_hours] = true if enforce
      Billing::Reservations::EnforcePostedHours.call(**args)
    end
  end

  def at(date, hhmm)
    @zone.parse("#{date} #{hhmm}")
  end

  test "blocks a 2 AM booking for a guest" do
    result = call_step(datetime_in: at(@tuesday, "02:00"))
    assert result.failure?
    assert_match(/open/i, result.message)
  end

  test "allows a weekend daytime booking (staffed-day flags don't bound self-serve bookings)" do
    # Prod audit 2026-08-07: weekend daytime day-pass usage is established,
    # accepted behavior — only the TIME-of-day window bounds bookings.
    result = call_step(datetime_in: at(@saturday, "10:00"))
    assert result.success?
  end

  test "blocks a booking that runs past close" do
    result = call_step(datetime_in: at(@tuesday, "19:30"), minutes: 60)
    assert result.failure?
  end

  test "allows an in-hours booking" do
    result = call_step(datetime_in: at(@tuesday, "10:00"))
    assert result.success?
  end

  test "allows a booking that ends exactly at close" do
    result = call_step(datetime_in: at(@tuesday, "19:00"), minutes: 60)
    assert result.success?
  end

  test "no-op when enforce_posted_hours is not set (admin on-behalf flows)" do
    result = call_step(datetime_in: at(@tuesday, "02:00"), enforce: false)
    assert result.success?
  end

  test "superadmin books outside posted hours" do
    user = ActsAsTenant.with_tenant(@operator) do
      create(:user, operator: @operator, superadmin: true,
             original_location: @location, current_location: @location)
    end
    result = call_step(datetime_in: at(@tuesday, "02:00"), user: user)
    assert result.success?
  end

  test "subscribed member books outside posted hours" do
    plans(:cowork_tahoe_full_time_plan).update!(location_id: @location.id)
    result = call_step(datetime_in: at(@tuesday, "02:00"), user: users(:cowork_tahoe_member))
    assert result.success?
  end
end
