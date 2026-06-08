require 'application_system_test_case'

class LocationCheckTest < ApplicationSystemTestCase
  # A logged-in user with no current_location no longer gets an in-app "pick a
  # location" gate while staying signed in. Operator::BaseController#reset_location
  # now defensively logs them out and sends them to the landing page, where a
  # multi-location operator renders the public "Select a location" picker.
  test "logged in user with no location is bounced to the location picker" do
    user = users(:cowork_tahoe_admin)
    operator = operators(:cowork_tahoe)
    # Second location → multi-location operator, so current_location won't be
    # auto-resolved to the only location.
    create(:location, operator: operator, name: "Other Location", allow_hourly: true, hourly_rate_in_cents: 500, working_day_start: "00:00", working_day_end: "23:59")
    user.update!(current_location: nil, original_location: nil)

    log_in(user)
    visit home_path
    assert_text "Select a location"

    visit doors_path
    assert_text "Select a location"
  end

  # Once a location is selected (here via the persisted user preference), the
  # logged-in user proceeds normally.
  test "logged in user with a current location can proceed" do
    user = users(:cowork_tahoe_admin) # fixture has current_location: cowork_tahoe_location
    log_in(user)

    visit doors_path
    assert_text "Building Access"

    visit home_path
    assert_text "Reserve Now"
  end

  test "non logged in user need to select location before proceeding" do
    user = users(:cowork_tahoe_member)
    operator = operators(:cowork_tahoe)
    other_location = create(:location, operator: operator, name: "Other Location", allow_hourly: true, hourly_rate_in_cents: 500, working_day_start: "00:00", working_day_end: "23:59")

    visit home_path

    assert_text "Select a location"

    click_on "Other Location"
    assert_text "Welcome to Other Location"
  end
end
