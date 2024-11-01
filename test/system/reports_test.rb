require 'application_system_test_case'

class ReportsTest < ApplicationSystemTestCase
  test "admin viewing reports" do
    log_in(users(:cowork_tahoe_admin))
    operator = operators(:cowork_tahoe)
    location = operator.locations.first
    other_location = create(:location, operator: operator)

    # create data for the reports
    # weekly updates
    weekly_update_1 = WeeklyUpdate.create!(
      week_start: Date.parse("2021-01-01"),
      week_end: Date.parse("2021-01-07"),
      operator: operator,
      location: location,
    )
    weekly_update_2 = WeeklyUpdate.create!(
      week_start: Date.parse("2021-01-08"),
      week_end: Date.parse("2021-01-14"),
      operator: operator,
      location: other_location,
    )

    # members
    location_user = create(:user, operator: operator, original_location: location, approved: true)
    location_user_2 = create(:user, operator: operator, original_location: location, approved: true)
    other_location_user = create(:user, operator: operator, original_location: other_location, approved: true)


    # view reports on main location
    visit reports_path
    # assert_text "2 active member"
    click_on "View Weekly Updates"
    assert_text "January 1, 2021 - January 7, 2021"
    assert_no_text "January 8, 2021 - January 14, 2021"


    # view reports on other location
    switch_to_location other_location
    visit reports_path
    # assert_text "1 active member"
    click_on "View Weekly Updates"
    assert_no_text "January 1, 2021 - January 7, 2021"
    assert_text "January 8, 2021 - January 14, 2021"

    # TODO: the rest of the tests
  end
end