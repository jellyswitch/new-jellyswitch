require 'application_system_test_case'

class FilterFeedItemsTest < ApplicationSystemTestCase
  test "posting post" do
    user = users(:cowork_tahoe_admin)
    log_in(user)
    operator = operators(:cowork_tahoe)
    location = locations(:cowork_tahoe_location)

    announcement = Announcement.create(operator: operator, location: location, body: "Question feed item", user: user)
    FeedItemCreator.create_feed_item(operator, location, users(:cowork_tahoe_admin), { announcement_id: announcement.id, type: "announcement", text: "Question?" }, created_at: Time.now)

    FeedItemCreator.create_feed_item(operator, location, users(:cowork_tahoe_admin), { type: "post", text: "Note feed item" }, created_at: Time.now)
    feed_item_note = FeedItem.last
    feed_item_note.text = "Note feed item"
    feed_item_note.save

    day_pass_type = DayPassType.create(operator: operator, location: location, name: "Day Pass")
    day_pass = DayPass.create(operator: operator, location: location, user: user, billable: user, day_pass_type: day_pass_type, day: Date.current)
    FeedItemCreator.create_feed_item(operator, location, users(:cowork_tahoe_admin), { day_pass_id: day_pass.id, type: "day-pass" }, created_at: Time.now)

    visit feed_items_path

    assert_text "Question feed item"
    assert_text "Note feed item"
    assert_text "bought a day pass"

    # filter questions
    find(".filter-question-feed-items").click
    assert_text "Question feed item"
    assert_no_text "Note feed item"
    assert_no_text "bought a day pass"

    # filter notes
    find(".filter-note-feed-items").click
    assert_no_text "Question feed item"
    assert_text "Note feed item"
    assert_no_text "bought a day pass"

    # filter activity
    find(".filter-activity-feed-items").click
    assert_no_text "Question feed item"
    assert_no_text "Note feed item"
    assert_text "bought a day pass"
  end
end