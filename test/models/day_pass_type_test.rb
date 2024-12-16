require "test_helper"

class DayPassTypeTest < ActiveSupport::TestCase
  setup do
    @location = locations(:cowork_tahoe_location)
    @user = users(:cowork_tahoe_member)
  end

  test "DayPassType.all_options_for_select returns all available day pass types for user with billing" do
    @user.stub(:has_billing_for_location?, true) do
      day_pass_types = DayPassType.all_options_for_select(@location, @user)

      assert_equal day_pass_types, DayPassType.where(location_id: @location.id).available
    end
  end

  test "DayPassType.all_options_for_select returns only free day pass types for user without billing" do
    @user.stub(:has_billing_for_location?, false) do
      day_pass_types = DayPassType.all_options_for_select(@location, @user)

      assert_equal day_pass_types, DayPassType.where(location_id: @location.id).available.free
    end
  end
end
