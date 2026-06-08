require 'application_system_test_case'

class ManagementNotesTest < ApplicationSystemTestCase
  test "posting post" do
    log_in(users(:cowork_tahoe_admin))
    operator = operators(:cowork_tahoe)
    other_location = create(:location, operator: operator)
    visit feed_items_path

    find("#new-management-note").click
    # Bootstrap data-toggle modal races jQuery binding in CI; same flake as
    # update_price_spec + feed_items_test. Trigger via .modal('show') as
    # an idempotent fallback.
    page.execute_script("$('#newModal').modal('show')")
    # The modal "What would you like to do?" now labels the note action
    # "Management note" (it links to the new-feed-item page, whose own heading
    # is still "Post a management note"). Scope to the modal so we don't match
    # the "Management notes" feed-filter link behind the overlay.
    within "#newModal" do
      click_on "Management note"
    end
    find("trix-editor").click.set("Test Note")
    find("#submit").click

    assert_text "Test Note"

    # change location
    switch_to_location(other_location)

    # user sees no post at the other location
    visit feed_items_path
    assert_no_text "Test Note"
  end
end