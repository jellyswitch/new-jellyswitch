require "test_helper"

# Permissions#has_building_access? backs the WEB Keys page list — it must
# apply the same posted-hours bound to day-pass access as the unlock gate
# (Api::V1::DoorUnlocking#user_can_access_building?), or the web list shows
# keys whose tap 403s (the exact list/unlock divergence PR #668 closed).
class UserDayPassHoursAccessTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @zone = ActiveSupport::TimeZone["Pacific Time (US & Canada)"]
    @tuesday = Date.current.next_occurring(:tuesday) + 7
    ActsAsTenant.with_tenant(@operator) do
      @location.update!(time_zone: "Pacific Time (US & Canada)",
                        working_day_start: "06:00", working_day_end: "20:00",
                        open_saturday: false, open_sunday: false)
      @guest = create(:user, operator: @operator, original_location: @location, current_location: @location)
      @type = create(:day_pass_type, operator: @operator, location: @location,
                     amount_in_cents: 4000, always_allow_building_access: false)
      @allday_type = create(:day_pass_type, operator: @operator, location: @location,
                            amount_in_cents: 4000, always_allow_building_access: true)
    end
  end

  def grant_pass(type)
    ActsAsTenant.with_tenant(@operator) do
      create(:day_pass, user: @guest, billable: @guest, operator: @operator,
             location: @location, day_pass_type: type, day: @tuesday)
    end
  end

  test "day pass grants building access during posted hours" do
    grant_pass(@type)
    travel_to @zone.parse("#{@tuesday} 10:00") do
      assert @guest.has_building_access?(@location)
    end
  end

  test "day pass does not grant building access outside posted hours" do
    grant_pass(@type)
    travel_to @zone.parse("#{@tuesday} 02:00") do
      assert_not @guest.has_building_access?(@location)
    end
  end

  test "always-allow pass type keeps access outside posted hours" do
    grant_pass(@allday_type)
    travel_to @zone.parse("#{@tuesday} 02:00") do
      assert @guest.has_building_access?(@location)
    end
  end
end
