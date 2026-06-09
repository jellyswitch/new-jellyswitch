require 'application_system_test_case'

class ManagementNotesTest < ApplicationSystemTestCase
  test "posting post" do
    log_in(users(:cowork_tahoe_admin))
    operator = operators(:cowork_tahoe)
    other_location = create(:location, operator: operator)

    # Go straight to the note form. The "What would you like to do?" modal that
    # links here is a Bootstrap data-toggle that flakes on navigation; the note
    # form itself is what we're exercising.
    visit new_feed_item_path

    # Regression: the note form switched to a Trix editor, but the old
    # disable_button left #submit permanently disabled (it listened for input on
    # the hidden field, which Trix doesn't fire there) — so notes couldn't be
    # posted. The button is now always submittable.
    assert_selector "trix-editor"
    # Drive Trix through its editor API — Capybara's .set/send_keys don't
    # reliably reach the <trix-editor> contenteditable in headless Chrome.
    page.execute_script("document.querySelector('trix-editor').editor.insertString('Test Note')")
    find("#submit").click

    assert_text "Test Note"

    # change location
    switch_to_location(other_location)

    # user sees no post at the other location
    visit feed_items_path
    assert_no_text "Test Note"
  end
end