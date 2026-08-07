require "test_helper"

# A plan grants building access at ITS OWN location (plans are stamped with
# the admin's location on create). Before this fix `grants_building_access?`
# ignored plan.location entirely, so an all_hours membership at one building
# of a multi-location operator opened every other building's doors too.
# Lenient edges match the day-pass scoping convention: a nil plan location
# stays operator-wide, a nil gate location keeps the unscoped behavior.
class PlanLocationBuildingAccessTest < ActiveSupport::TestCase
  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    ActsAsTenant.with_tenant(@operator) do
      @location.update!(time_zone: "Pacific Time (US & Canada)",
                        working_day_start: "06:00", working_day_end: "20:00")
      @other_location = create(:location, operator: @operator, name: "Fulton Annex",
                               time_zone: "Pacific Time (US & Canada)",
                               working_day_start: "06:00", working_day_end: "20:00")
      @plan = create(:plan, operator: @operator, location: @location,
                     building_access_level: :all_hours)
    end
  end

  test "all_hours grants at the plan's own location" do
    assert @plan.grants_building_access?(@location)
  end

  test "all_hours does not grant at another location" do
    assert_not @plan.grants_building_access?(@other_location)
  end

  test "business_hours never grants at another location, even while it is open" do
    @plan.update!(building_access_level: :business_hours)
    zone = ActiveSupport::TimeZone["Pacific Time (US & Canada)"]
    open_hour = zone.parse("#{Date.current.next_occurring(:tuesday) + 7} 10:00")
    assert @other_location.open_at?(open_hour), "test setup: the other location should be open"
    assert_not @plan.grants_building_access?(@other_location, open_hour)
  end

  test "a plan with no location stays operator-wide" do
    @plan.update!(location: nil)
    assert @plan.grants_building_access?(@other_location)
  end

  test "a nil gate location keeps the unscoped behavior" do
    assert @plan.grants_building_access?(nil)
  end
end
