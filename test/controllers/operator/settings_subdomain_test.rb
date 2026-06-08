require "test_helper"

class Operator::SettingsSubdomainTest < ActionDispatch::IntegrationTest
  setup do
    setup_initial_user_fixtures
    @operator = operators(:cowork_tahoe)
    @user     = users(:cowork_tahoe_admin)
  end

  test "super admin can change the subdomain" do
    @user.update_columns(role: "superadmin", superadmin: true)
    log_in @user
    patch settings_update_subdomain_path, params: { operator: { subdomain: "renamed-space" } }, env: default_env
    assert_equal "renamed-space", @operator.reload.subdomain
  end

  test "a normal admin cannot change the subdomain" do
    @user.update_columns(role: "admin", superadmin: false)
    original = @operator.subdomain
    log_in @user
    patch settings_update_subdomain_path, params: { operator: { subdomain: "hacked" } }, env: default_env
    assert_equal original, @operator.reload.subdomain
  end
end
