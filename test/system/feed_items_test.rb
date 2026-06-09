require "application_system_test_case"

class FeedItemsTest < ApplicationSystemTestCase
  test "visiting the index" do
    log_in(users(:cowork_tahoe_admin))
  
    assert_text "What's Happening?"
  end

  test "creating a new management note" do
    log_in(users(:cowork_tahoe_admin))

    # Go straight to the note form — the "What would you like to do?" modal is a
    # Bootstrap data-toggle that flakes on navigation in headless Chrome.
    visit new_feed_item_path

    assert_selector 'trix-editor'
    # Drive Trix via its editor API; Capybara's .set/send_keys don't reliably
    # reach the <trix-editor> contenteditable here.
    page.execute_script("document.querySelector('trix-editor').editor.insertString('Test Note')")
    find('#submit').click

    assert_text 'Test Note'
  end
end
