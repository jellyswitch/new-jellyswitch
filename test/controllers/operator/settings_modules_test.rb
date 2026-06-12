require 'test_helper'

class Operator::SettingsModulesTest < ActionDispatch::IntegrationTest
  setup do
    setup_initial_user_fixtures
    @admin    = users(:cowork_tahoe_admin)
    @operator = @admin.operator
    @location = locations(:cowork_tahoe_location)
    log_in @admin
  end

  test "GET modules renders as admin" do
    get settings_modules_path, env: default_env
    assert_response :success
  end

  # Every module policy and the plans page read location.<module>_enabled. The
  # Settings -> Modules form previously wrote the operator columns, which gating
  # never reads, so toggling a module there did nothing (e.g. childcare kept
  # showing on plans). It must write the LOCATION columns (the source of truth).
  test "update_modules persists to the current location, not the operator" do
    @location.update!(childcare_enabled: true)
    @operator.update!(childcare_enabled: true)

    patch settings_update_modules_path, env: default_env, params: {
      location: {
        announcements_enabled: "1",
        events_enabled: "1",
        door_integration_enabled: "1",
        rooms_enabled: "1",
        offices_enabled: "1",
        bulletin_board_enabled: "1",
        childcare_enabled: "0",
        crm_enabled: "1",
        credits_enabled: "0",
      },
    }

    assert_redirected_to settings_modules_path
    assert_equal false, @location.reload.childcare_enabled,
      "location.childcare_enabled (what the plans page reads) must reflect the toggle"
  end

  # The single-toggle /modules path guards this; the bulk form must too, or an
  # admin could strand active leases by disabling the Offices module.
  test "update_modules refuses to disable Offices while active leases exist" do
    @location.update!(offices_enabled: true)
    Location.any_instance.stubs(:has_active_office_leases?).returns(true)

    patch settings_update_modules_path, env: default_env, params: {
      location: { offices_enabled: "0" },
    }

    assert_response :unprocessable_entity
    assert @location.reload.offices_enabled,
      "offices must stay enabled while leases are active"
  end
end
