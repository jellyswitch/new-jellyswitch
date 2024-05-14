require "test_helper"

class DayPassTypeTest < ActiveSupport::TestCase
  setup do
    @operator = operators(:cowork_tahoe)
    @user = users(:cowork_tahoe_member)
  end

  test "DayPassType.all_options_for_select returns all available day pass types for user with billing" do
    @user.stub(:has_billing?, true) do
      day_pass_types = DayPassType.all_options_for_select(@operator, @user)

      assert_equal day_pass_types, DayPassType.where(operator_id: @operator.id).available
    end
  end

  test "DayPassType.all_options_for_select returns only free day pass types for user without billing" do
    @user.stub(:has_billing?, false) do
      day_pass_types = DayPassType.all_options_for_select(@operator, @user)

      assert_equal day_pass_types, DayPassType.where(operator_id: @operator.id).available.free
    end
  end
end
