require 'application_system_test_case'

class MemberFeedbacksTest < ApplicationSystemTestCase
  setup do
    stub_request(:post, "https://fcm.googleapis.com/fcm/send")
      .to_return(
        status: 200
      )
  end

  teardown do
    WebMock.reset!
  end

  test "member posting feedback" do
    log_in(users(:cowork_tahoe_admin))
    operator = operators(:cowork_tahoe)
    other_location = create(:location, operator: operator)
    visit home_path
    fill_in "Comment", with: "Test Member Feedback"
    # disable_button partial initially disables #submit and enables it on
    # text input; trigger the jQuery input listener explicitly since
    # Capybara's fill_in events don't always reach the bound handler.
    page.execute_script("$('#text').trigger('input')")
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