require "test_helper"

# The per-person "Always allow building access" checkbox was honored by the
# Keys list (Permissions#has_building_access?) but NOT by the unlock gate
# (Api::V1::DoorUnlocking#user_can_access_building?), so the app showed the
# doors and the tap failed. All gates now agree (PR #668 lockstep), at the
# person's HOME space; a person with no home space keeps operator-wide access.
class UserAlwaysAllowAccessTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  class UnlockGate
    include Api::V1::DoorUnlocking
    public :user_can_access_building?
  end

  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @zone = ActiveSupport::TimeZone["Pacific Time (US & Canada)"]
    @saturday = Date.current.next_occurring(:saturday) + 7
    ActsAsTenant.with_tenant(@operator) do
      @location.update!(time_zone: "Pacific Time (US & Canada)",
                        working_day_start: "06:00", working_day_end: "20:00",
                        open_saturday: false, open_sunday: false)
      @other_location = create(:location, operator: @operator, name: "Second Space",
                               time_zone: "Pacific Time (US & Canada)")
      @cleaner = create(:user, operator: @operator, name: "Cleaner Cleo", email: "cleo@example.com",
                        always_allow_building_access: true,
                        original_location: @location, current_location: @location)
    end
    @gate = UnlockGate.new
  end

  def at_2am_saturday(&block)
    travel_to(@zone.parse("#{@saturday} 02:00"), &block)
  end

  test "always-allow person can unlock their home space 24/7 with no membership, and every gate agrees" do
    at_2am_saturday do
      assert_not @cleaner.has_active_subscription?
      assert @cleaner.has_building_access?(@location)            # Keys list
      assert @gate.user_can_access_building?(@cleaner, @location) # unlock (was false)
      assert @cleaner.allowed_in_for_door_access?(@location)      # legacy web open
    end
  end

  test "always-allow is limited to the person's home space" do
    at_2am_saturday do
      assert_not @cleaner.has_building_access?(@other_location)
      assert_not @gate.user_can_access_building?(@cleaner, @other_location)
      assert_not @cleaner.allowed_in_for_door_access?(@other_location)
    end
  end

  test "a person with no home space keeps operator-wide always-allow access" do
    @cleaner.update_columns(original_location_id: nil)
    at_2am_saturday do
      assert @cleaner.has_building_access?(@other_location)
      assert @gate.user_can_access_building?(@cleaner, @other_location)
    end
  end

  test "approval and the box are still required" do
    @cleaner.update!(approved: false)
    at_2am_saturday { assert_not @gate.user_can_access_building?(@cleaner, @location) }

    @cleaner.update!(approved: true, always_allow_building_access: false)
    at_2am_saturday { assert_not @gate.user_can_access_building?(@cleaner, @location) }
  end
end
