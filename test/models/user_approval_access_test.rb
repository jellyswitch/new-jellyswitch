require "test_helper"

# Permissions#has_building_access? backs the WEB Keys page — it must apply the
# same approval hard gate as the unlock path (Api::V1::DoorUnlocking), or the
# web list shows keys whose tap 403s (the PR #668 list/unlock invariant).
class UserApprovalAccessTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @zone = ActiveSupport::TimeZone["Pacific Time (US & Canada)"]
    @tuesday = Date.current.next_occurring(:tuesday) + 7
    ActsAsTenant.with_tenant(@operator) do
      @location.update!(time_zone: "Pacific Time (US & Canada)",
                        working_day_start: "06:00", working_day_end: "20:00")
      @type = create(:day_pass_type, operator: @operator, location: @location, amount_in_cents: 4000)
    end
  end

  def guest_with_pass(approved:)
    ActsAsTenant.with_tenant(@operator) do
      user = create(:user, operator: @operator, approved: approved,
                    original_location: @location, current_location: @location)
      create(:day_pass, user: user, billable: user, operator: @operator,
             location: @location, day_pass_type: @type, day: @tuesday)
      user
    end
  end

  test "unapproved user with a day pass has no building access" do
    guest = guest_with_pass(approved: false)
    travel_to @zone.parse("#{@tuesday} 10:00") do
      assert_not guest.has_building_access?(@location)
    end
  end

  test "approved user with a day pass has building access" do
    guest = guest_with_pass(approved: true)
    travel_to @zone.parse("#{@tuesday} 10:00") do
      assert guest.has_building_access?(@location)
    end
  end

  test "staff keep building access regardless of the approved flag" do
    admin = users(:cowork_tahoe_admin)
    admin.update!(approved: false)
    travel_to @zone.parse("#{@tuesday} 10:00") do
      assert admin.has_building_access?(@location)
    end
  end
end
