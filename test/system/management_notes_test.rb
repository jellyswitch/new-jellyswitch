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
    click_on "Post a management note"
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