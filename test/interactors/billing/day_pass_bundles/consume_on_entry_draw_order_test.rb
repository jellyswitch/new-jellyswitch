require "test_helper"

# The door burn must use DayPassBundle.draw_order (soonest-expiring first,
# NULLs/perpetual last — ADR 0018): a member holding an expiring pack plus a
# perpetual one spends the expiring pack on entry. An unordered pick falls
# back to insertion order and can burn the perpetual pack while the expiring
# passes lapse.
class Billing::DayPassBundles::ConsumeOnEntryDrawOrderTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @zone = ActiveSupport::TimeZone["Pacific Time (US & Canada)"]
    @tuesday = Date.current.next_occurring(:tuesday) + 7
    ActsAsTenant.with_tenant(@operator) do
      @location.update!(time_zone: "Pacific Time (US & Canada)",
                        working_day_start: "06:00", working_day_end: "20:00")
      @guest = create(:user, operator: @operator, original_location: @location, current_location: @location)
      type = create(:day_pass_type, operator: @operator, location: @location)
      # Perpetual pack created FIRST (lowest id) so an unordered pick would
      # take it; draw_order must pass over it for the expiring pack.
      @perpetual = create(:day_pass_bundle, user: @guest, billable: @guest, operator: @operator,
                          location: @location, day_pass_type: type)
      @expiring = create(:day_pass_bundle, user: @guest, billable: @guest, operator: @operator,
                         location: @location, day_pass_type: type,
                         expires_at: @zone.parse("#{@tuesday} 12:00") + 10.days)
    end
  end

  def enter!
    travel_to @zone.parse("#{@tuesday} 10:30") do
      Billing::DayPassBundles::ConsumeOnEntry.call(user: @guest, location: @location)
    end
  end

  test "entry burns the soonest-expiring bundle, not the perpetual one" do
    result = enter!
    assert_equal :redeemed, result.outcome
    assert_equal 4, @expiring.reload.passes_remaining
    assert_equal 5, @perpetual.reload.passes_remaining
  end

  test "entry falls back to the perpetual bundle once the expiring pack is empty" do
    ActsAsTenant.with_tenant(@operator) { @expiring.update!(passes_remaining: 0) }
    result = enter!
    assert_equal :redeemed, result.outcome
    assert_equal 0, @expiring.reload.passes_remaining
    assert_equal 4, @perpetual.reload.passes_remaining
  end
end
