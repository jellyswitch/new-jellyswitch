require 'application_system_test_case'

class ModulesTest < ApplicationSystemTestCase
  test "superadmin viewing modules" do
    user = users(:cowork_tahoe_admin)
    user.update role: User::SUPERADMIN
    log_in(user)

    operator = operators(:cowork_tahoe)
    location = operator.locations.first

    visit modules_path

    assert_text "Enable and disable Jellyswitch modules to fully customize your experience."

    within "a[href='/modules/bulletin_board']" do
      # First verify it shows toggle-on
      assert_selector "i.fa-toggle-on"

      # Click the link
      find("i.fas").click

      # Verify toggle-on is gone and toggle-off is present
      assert_no_selector "i.fa-toggle-on"
      assert_selector "i.fa-toggle-off"
    end
  end
end