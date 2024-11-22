require 'application_system_test_case'

class EventsTest < ApplicationSystemTestCase
  test "posting event" do
    log_in(users(:cowork_tahoe_admin))
    operator = operators(:cowork_tahoe)
    other_location = create(:location, operator: operator)
    visit new_event_path
    fill_in "Title", with: "Test Event Title"
    find('#starts_at').click
    fill_in "Specific address (if different from location's address)", with: "Test Event Address"
    fill_in "Description", with: "Test Event Description"
    click_on "Create event"

    assert_text "Event created."
    assert_text "What's Happening?"
    assert_text "Test Event Title"
    assert_text "Test Event Description"
    assert_text "Test Event Address"

    # user sees event at the location
    visit home_path
    assert_text "Test Event Title"

    # user sees the event in the list
    visit events_path
    assert_text "Test Event Title"

    # change location
    switch_to_location(other_location)

    # user sees no event at the other location
    visit home_path
    assert_no_text "Test Event Title"

    # user sees no event in the list at the other location
    visit events_path
    assert_no_text "Test Event Title"
  end
end