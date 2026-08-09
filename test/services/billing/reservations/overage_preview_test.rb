require "test_helper"

class Billing::Reservations::OveragePreviewTest < ActiveSupport::TestCase
  setup { @operator = operators(:cowork_tahoe); @location = locations(:cowork_tahoe_location) }

  test "prospective overage against a limited type" do
    ActsAsTenant.with_tenant(@operator) do
      @location.update!(overage_rate_in_cents: 6000) # $60/hr
      user = create(:user, operator: @operator, original_location: @location, current_location: @location)
      type = create(:day_pass_type, operator: @operator, location: @location, included_meeting_room_minutes: 60)
      cents = Billing::Reservations::OveragePreview.cents(
        user: user, location: @location, date: Date.current + 3, minutes: 90, day_pass_type: type)
      assert_equal 3000, cents # 30 min over × $60/hr
    end
  end

  test "no overage within allowance or for an unlimited type" do
    ActsAsTenant.with_tenant(@operator) do
      user = create(:user, operator: @operator, original_location: @location, current_location: @location)
      limited = create(:day_pass_type, operator: @operator, location: @location, included_meeting_room_minutes: 120)
      assert_equal 0, Billing::Reservations::OveragePreview.cents(
        user: user, location: @location, date: Date.current + 3, minutes: 60, day_pass_type: limited)

      unlimited = create(:day_pass_type, operator: @operator, location: @location, included_meeting_room_minutes: nil)
      assert_equal 0, Billing::Reservations::OveragePreview.cents(
        user: user, location: @location, date: Date.current + 3, minutes: 999, day_pass_type: unlimited)
    end
  end

  # ADR 0026: a Day Office hold is a $0 posted-hours reservation minted BY the
  # office pass purchase — it must never count as "other usage" against the
  # very allowance the pass grants. Mirrors ChargeCalculator#day_pass_overage_cents
  # (see that file's own ADR 0026 test) — this preview must agree with it, or a
  # member sees one price quoted and a different one actually captured.
  test "office hold's own minutes don't count as prior usage in the preview (ADR 0026)" do
    ActsAsTenant.with_tenant(@operator) do
      # A non-zero rate matters: at the default $0/min any leaked minutes still
      # price at 0, which would let this test pass even if the exclusion regressed.
      @location.update!(overage_rate_in_cents: 6000, working_day_start: "08:00", working_day_end: "18:00")
      user = create(:user, operator: @operator, original_location: @location, current_location: @location)
      office_type = create(:day_pass_type, operator: @operator, location: @location,
                           kind: "day_office", included_meeting_room_minutes: 60)
      pool_room = create(:room, operator: @operator, location: @location,
                         hourly_rate_in_cents: 0, include_with_day_pass: true)
      office_type.assign_office_rooms!({ pool_room.id => 1 })
      day = Date.current + 7
      office_pass = create(:day_pass, user: user, billable: user, operator: @operator,
                           location: @location, day_pass_type: office_type, day: day)
      hold = DayOffices::Allocator.allocate!(day_pass: office_pass)
      assert_equal 600, hold.minutes # sanity: a regression here would silently defeat the assertion below

      cents = Billing::Reservations::OveragePreview.cents(
        user: user, location: @location, date: day, minutes: 30, day_pass_type: office_type)
      assert_equal 0, cents # 30 <= 60 free, IF the hold's 600 min are excluded (else 3000¢)
    end
  end
end
