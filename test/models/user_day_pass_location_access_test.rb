require "test_helper"

# Permissions#has_building_access? (web Keys page + mobile door-access view)
# must scope day-pass access to the location being asked about, mirroring the
# unlock gate (Api::V1::DoorUnlocking#user_can_access_building?).
# has_active_day_pass_at_location? was already scoped with the lenient
# for_location; the always-allow pass-TYPE escape hatch
# (has_building_access_day_pass?) was NOT — a 24/7 pass bought for one
# location granted keys at every other location of the operator.
class UserDayPassLocationAccessTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @zone = ActiveSupport::TimeZone["Pacific Time (US & Canada)"]
    @tuesday = Date.current.next_occurring(:tuesday) + 7
    ActsAsTenant.with_tenant(@operator) do
      @location.update!(time_zone: "Pacific Time (US & Canada)",
                        working_day_start: "06:00", working_day_end: "20:00")
      @other_location = create(:location, operator: @operator, name: "Fulton Annex")
      @guest = create(:user, operator: @operator, original_location: @location, current_location: @location)
      @type = create(:day_pass_type, operator: @operator, location: @location,
                     amount_in_cents: 4000, always_allow_building_access: false)
      @allday_type = create(:day_pass_type, operator: @operator, location: @other_location,
                            amount_in_cents: 4000, always_allow_building_access: true)
    end
  end

  def grant_pass(location:, type:)
    ActsAsTenant.with_tenant(@operator) do
      create(:day_pass, user: @guest, billable: @guest, operator: @operator,
             location: location, day_pass_type: type, day: @tuesday)
    end
  end

  test "an always-allow pass for another location does not grant access here" do
    grant_pass(location: @other_location, type: @allday_type)
    travel_to @zone.parse("#{@tuesday} 10:00") do
      assert_not @guest.has_building_access?(@location)
    end
  end

  test "an always-allow pass with no location still grants 24/7 access (legacy leniency)" do
    grant_pass(location: nil, type: @allday_type)
    travel_to @zone.parse("#{@tuesday} 02:00") do
      assert @guest.has_building_access?(@location)
    end
  end

  test "a regular pass for another location does not grant access here" do
    grant_pass(location: @other_location, type: @type)
    travel_to @zone.parse("#{@tuesday} 10:00") do
      assert_not @guest.has_building_access?(@location)
    end
  end

  test "a regular pass for this location still grants access here" do
    grant_pass(location: @location, type: @type)
    travel_to @zone.parse("#{@tuesday} 10:00") do
      assert @guest.has_building_access?(@location)
    end
  end
end
