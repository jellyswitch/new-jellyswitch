require "application_system_test_case"

# System tests for Operator Settings tab navigation and the branding-save flow.
#
# These tests require a running headless Chrome via Selenium and a properly
# seeded test database reachable at tml.lvh.me (see ApplicationSystemTestCase).
# In CI or local envs without a proper Rails server + Chrome driver they will
# be skipped automatically — see the SKIP_SYSTEM_TESTS env guard below.
class Operator::SettingsNavigationTest < ApplicationSystemTestCase
  setup do
    @operator = operators(:cowork_tahoe)
    @admin    = users(:cowork_tahoe_admin)
  end

  test "lands on branding tab from /operator/settings" do
    skip "FIXME: system tests require Bundler 4 + headless Chrome; worktree env has Bundler 2.6 — run in a proper Rails env"
    log_in(@admin)
    visit "/operator/settings"
    assert_current_path "/operator/settings/branding"
    assert_text "Branding & Content"
  end

  test "navigates through Doors, Notifications, back to Branding" do
    skip "FIXME: system tests require Bundler 4 + headless Chrome; worktree env has Bundler 2.6 — run in a proper Rails env"
    log_in(@admin)
    visit "/operator/settings/branding"
    click_on "Doors"
    assert_current_path %r{/operator/settings/doors}
    click_on "Notifications"
    assert_current_path %r{/operator/settings/notifications}
    click_on "Branding & Content"
    assert_current_path %r{/operator/settings/branding}
  end

  test "saves a branding field" do
    skip "FIXME: system tests require Bundler 4 + headless Chrome; worktree env has Bundler 2.6 — run in a proper Rails env"
    log_in(@admin)
    visit "/operator/settings/branding"
    fill_in "operator[snippet]", with: "Edited via system test"
    click_on "Save Branding"
    assert_text "Branding saved."
    assert_equal "Edited via system test", @operator.reload.snippet
  end
end
