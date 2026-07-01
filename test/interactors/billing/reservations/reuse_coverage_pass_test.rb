require "test_helper"

class Billing::Reservations::ReuseCoveragePassTest < ActiveSupport::TestCase
  setup do
    @operator = operators(:cowork_tahoe); @location = locations(:cowork_tahoe_location)
  end

  test "re-dates a spare pass onto the reservation and links it" do
    ActsAsTenant.with_tenant(@operator) do
      user = create(:user, operator: @operator, original_location: @location, current_location: @location)
      room = create(:room, operator: @operator, location: @location, hourly_rate_in_cents: 0, include_with_day_pass: true)
      dpt  = create(:day_pass_type, operator: @operator, location: @location, included_meeting_room_minutes: 60)
      old_res = create(:reservation, user: user, room: room, minutes: 60)
      spare = create(:day_pass, user: user, billable: user, operator: @operator, location: @location,
                     day_pass_type: dpt, day: Date.current + 5, reservation: old_res)
      old_res.update!(cancelled: true) # cancel AFTER linking (acts_as_tenant; see GOTCHA 2)
      new_res = create(:reservation, user: user, room: room, minutes: 60,
                       datetime_in: (Date.current + 3).to_time + 9.hours)

      result = Billing::Reservations::ReuseCoveragePass.call(
        reservation: new_res, user: user, use_existing_pass: true, coverage_pass: spare)

      assert_equal :reused, result.outcome
      assert_equal (Date.current + 3), spare.reload.day
      assert_equal new_res.id, spare.reservation_id
    end
  end

  test "no-op unless use_existing_pass" do
    ActsAsTenant.with_tenant(@operator) do
      user = create(:user, operator: @operator, original_location: @location, current_location: @location)
      res = create(:reservation, user: user, room: create(:room, operator: @operator, location: @location, hourly_rate_in_cents: 0, include_with_day_pass: true), minutes: 60)
      result = Billing::Reservations::ReuseCoveragePass.call(reservation: res, user: user, use_existing_pass: false)
      assert_nil result.outcome
    end
  end
end
