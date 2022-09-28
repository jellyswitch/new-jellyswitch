require "application_system_test_case"

class FeedItemsTest < ApplicationSystemTestCase
  test "visiting the index" do
    log_in(users(:cowork_tahoe_admin))
    visit feed_items_path
  
    assert_text "What's Happening?"
  end

  test "creating a new management note" do
    log_in(users(:cowork_tahoe_admin))
    visit feed_items_path
    find('#new-management-note').click
    click_on 'Post a management note'
    fill_in 'Type a new management note...', with: 'Test Note'
    click_on 'Post management note'
  
    assert_text 'Test Note'
  end
end
