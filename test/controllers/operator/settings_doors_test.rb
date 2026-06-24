require 'test_helper'

class Operator::SettingsDoorsTest < ActionDispatch::IntegrationTest
  setup do
    setup_initial_user_fixtures
    @admin    = users(:cowork_tahoe_admin)
    @operator = @admin.operator
    log_in @admin
  end

  test "GET doors renders as admin" do
    get settings_doors_path, env: default_env
    assert_response :success
  end

  # ADR 0013: the reservation door-access window is an operator setting edited on
  # the Doors tab.
  test "update_doors saves building_access_window_minutes" do
    patch settings_update_doors_path, env: default_env, params: {
      operator: { building_access_window_minutes: 90 },
    }

    assert_redirected_to settings_doors_path
    assert_equal 90, @operator.reload.building_access_window_minutes
  end
end
