require "application_system_test_case"

class FeedItemsTest < ApplicationSystemTestCase
  test "visiting the index" do
    log_in(users(:cowork_tahoe_admin))
  
    assert_text "What's Happening?"
  end

  test "creating a new management note" do
    log_in(users(:cowork_tahoe_admin))

    find('#new-management-note').click
    click_on 'Post a management note'
    find('trix-editor').click.set('Test Note')
    find('#submit').click

    assert_text 'Test Note'
  end
end
