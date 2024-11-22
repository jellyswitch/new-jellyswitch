require 'application_system_test_case'

class DayPassAccessTest < ApplicationSystemTestCase
  setup do
    StripeMock.start

    @user = users(:cowork_tahoe_non_member)
    setup_stripe_no_subscription
  end

  teardown do
    StripeMock.stop
  end

  test "user accesses a location via its daypass" do
    log_in(users(:cowork_tahoe_non_member))
    operator = operators(:cowork_tahoe)
    other_location = create(:location, operator: operator)
    visit home_path

    assert_text "Please select an option below."

    click_on "Buy a day pass"
    click_on "Select Standard Day Pass"

    assert_text "$200"

    click_on "Confirm and purchase"

    assert_text "Building Access"

    # change location
    switch_to_location(other_location)

    assert_no_text "Building Access"
    assert_text "Please select an option below."
  end
end