require 'application_system_test_case'

class MemberFeedbacksTest < ApplicationSystemTestCase
  test "member posting feedback" do
    log_in(users(:cowork_tahoe_admin))
    operator = operators(:cowork_tahoe)
    other_location = create(:location, operator: operator)
    visit home_path
    fill_in "Comment", with: "Test Member Feedback"
    click_on "Notify a staff member"

    assert_text "Thank you for your feedback!"

    # admin sees the feedback in the feeds
    visit feed_items_path
    assert_text "Test Member Feedback"

    # change location
    switch_to_location(other_location)

    # admin does not see the feedback in the feeds of the other location
    visit feed_items_path
    assert_no_text "Test Member Feedback"
  end
end