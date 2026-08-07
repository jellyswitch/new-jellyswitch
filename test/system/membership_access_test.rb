require 'application_system_test_case'

class MembershipAccessTest < ApplicationSystemTestCase
  test "user accesses a location via membership" do
    log_in(users(:cowork_tahoe_member))
    operator = operators(:cowork_tahoe)
    other_location = create(:location, operator: operator)
    visit home_path

    assert_text "Building Access"

    # A membership is per-location: its plan grants access at the plan's own
    # building only, so switching to the operator's other location lands on
    # the no-access options page. (A plan with no location would keep
    # operator-wide access — see PlanLocationBuildingAccessTest.)
    switch_to_location(other_location)

    assert_no_text "Building Access"
    assert_text "Please select an option below."
  end

  test "admin accesses a location without membership" do
    log_in(users(:cowork_tahoe_admin))
    operator = operators(:cowork_tahoe)
    other_location = create(:location, operator: operator)
    visit home_path

    assert_text "Building Access"

    # change location
    switch_to_location(other_location)

    assert_no_text "Building Access"
    assert_text "Please select an option below."
  end
end