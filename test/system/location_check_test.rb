require 'application_system_test_case'

class LocationCheckTest < ApplicationSystemTestCase
  test "logged in user need to select location before proceeding" do
    user = users(:cowork_tahoe_admin)
    operator = operators(:cowork_tahoe)
    other_location = create(:location, operator: operator, name: "Other Location", allow_hourly: true, hourly_rate_in_cents: 500, working_day_start: "00:00", working_day_end: "23:59")

    log_in(user)
    visit home_path

    assert_text "Select a location"

    visit doors_path
    assert_text "Select a location"

    switch_to_location(operator.locations.first)
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