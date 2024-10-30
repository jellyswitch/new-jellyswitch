require 'application_system_test_case'

class AnnouncementsTest < ApplicationSystemTestCase
  test "posting announcement note" do
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
    assert_text "Test announcement"

    # change location
    if page.has_link?("Change Location")
      click_on "Change Location"
    else
      find(".navbar-toggler").click
      click_on "Change Location"
    end
    page.find_button(other_location.name).click
    wait_for_turbo

    # user sees no announcement at the other location
    visit home_path
    assert_no_text "posted an announcement"
    assert_no_text "Test announcement"

    # admin sees no feed item at the other location
    visit feed_items_path
    assert_no_text "Test announcement"
  end
end