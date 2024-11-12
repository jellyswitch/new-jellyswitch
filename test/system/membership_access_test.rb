require 'application_system_test_case'

class MembershipAccessTest < ApplicationSystemTestCase
  test "user accesses a location via membership" do
    log_in(users(:cowork_tahoe_member))
    operator = operators(:cowork_tahoe)
    other_location = create(:location, operator: operator)
    visit home_path

    assert_text "Building Access"

    # change location
    switch_to_location(other_location)

    assert_text "Building Access"
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