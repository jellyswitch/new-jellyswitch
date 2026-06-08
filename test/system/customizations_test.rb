require 'application_system_test_case'

# The legacy per-location "Customize Jellyswitch" surface (with its "Manage
# <location>" links) was removed. `customization_path` is now a 301
# legacy_redirect to the new Settings area (Operator::SettingsController), which
# is gated to admins/superadmins by #require_admin_or_superadmin!. These tests
# assert that gate — the current behavior — rather than the removed UI.
class CustomizationsTest < ApplicationSystemTestCase
  test "superadmin is redirected from legacy customization into settings" do
    user = users(:cowork_tahoe_admin)
    user.update role: User::SUPERADMIN
    log_in(user)

    visit customization_path

    assert_current_path settings_branding_path
    assert_button "Save Branding"
  end

  test "admin is redirected from legacy customization into settings" do
    log_in(users(:cowork_tahoe_admin))

    visit customization_path

    assert_current_path settings_branding_path
    assert_button "Save Branding"
  end

  test "general manager is denied access to settings" do
    log_in(users(:cowork_tahoe_general_manager))

    visit customization_path

    assert_text "Admins only."
    assert_no_button "Save Branding"
  end

  test "community manager is denied access to settings" do
    log_in(users(:cowork_tahoe_community_manager))

    visit customization_path

    assert_text "Admins only."
    assert_no_button "Save Branding"
  end
end
