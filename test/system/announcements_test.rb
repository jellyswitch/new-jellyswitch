require 'application_system_test_case'

class AnnouncementsTest < ApplicationSystemTestCase
  setup do
    stub_request(:post, "https://fcm.googleapis.com/fcm/send")
      .to_return(
        status: 200
      )
  end

  teardown do
    WebMock.reset!
  end

  test "posting announcement note" do
    with_sidekiq_inline do
      log_in(users(:cowork_tahoe_admin))
      operator = operators(:cowork_tahoe)
      other_location = create(:location, operator: operator)
      visit new_announcement_path
      fill_in "text", with: "Test announcement"
      click_on "Post announcement"

      assert_text "Test announcement"

      # user sees announcement at the location
      visit home_path
      assert_text "posted an announcement"
      assert_text "Test announcement"

      # admin sees the corresponding feed item
      visit feed_items_path
      assert_text "posted an announcement"
      # assert this text only appears once
      assert_selector(".feed-item", count: 1)
      assert_text "Test announcement"

      # admin sees the announcement in the list
      visit announcements_path
      assert_text "Test announcement"

      # change location
      switch_to_location(other_location)

      # user sees no announcement at the other location
      visit home_path
      assert_no_text "posted an announcement"
      assert_no_text "Test announcement"

      # admin sees no feed item at the other location
      visit feed_items_path
      assert_no_text "Test announcement"

      # admin sees no announcement in the list at the other location
      visit announcements_path
      assert_no_text "Test announcement"
    end
  end
end