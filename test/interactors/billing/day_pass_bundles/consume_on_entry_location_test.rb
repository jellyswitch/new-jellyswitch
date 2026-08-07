require "test_helper"

# Guard 3 ("reservation today") must be scoped to the building being entered:
# a booking at ANOTHER building doesn't cover entry here, so it must not
# suppress the bundle burn — otherwise a member holding a booking at
# location A walks through location B's door on a B bundle without spending
# a day.
class Billing::DayPassBundles::ConsumeOnEntryLocationTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @zone = ActiveSupport::TimeZone["Pacific Time (US & Canada)"]
    @tuesday = Date.current.next_occurring(:tuesday) + 7
    ActsAsTenant.with_tenant(@operator) do
      @location.update!(time_zone: "Pacific Time (US & Canada)",
                        working_day_start: "06:00", working_day_end: "20:00")
      @other_location = create(:location, operator: @operator, name: "Fulton Annex",
                               time_zone: "Pacific Time (US & Canada)",
                               working_day_start: "06:00", working_day_end: "20:00")
      @guest = create(:user, operator: @operator, original_location: @location, current_location: @location)
      type = create(:day_pass_type, operator: @operator, location: @other_location)
      @bundle = create(:day_pass_bundle, user: @guest, billable: @guest, operator: @operator,
                       location: @other_location, day_pass_type: type)
    end
  end

  def reserve(location)
    ActsAsTenant.with_tenant(@operator) do
      room = create(:room, operator: @operator, location: location)
      create(:reservation, user: @guest, room: room,
             datetime_in: @zone.parse("#{@tuesday} 10:00"), minutes: 60)
    end
  end

  test "a reservation at another building does not suppress the burn here" do
    reserve(@location)
    travel_to @zone.parse("#{@tuesday} 10:30") do
      result = Billing::DayPassBundles::ConsumeOnEntry.call(user: @guest, location: @other_location)
      assert_equal :redeemed, result.outcome
    end
    assert_equal 4, @bundle.reload.passes_remaining
  end

  test "a reservation at this building still covers the entry (no burn)" do
    reserve(@other_location)
    travel_to @zone.parse("#{@tuesday} 10:30") do
      result = Billing::DayPassBundles::ConsumeOnEntry.call(user: @guest, location: @other_location)
      assert_equal :already_covered, result.outcome
    end
    assert_equal 5, @bundle.reload.passes_remaining
  end
end
