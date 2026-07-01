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
end
