require 'application_system_test_case'

class PostsTest < ApplicationSystemTestCase
  test "posting post" do
    log_in(users(:cowork_tahoe_admin))
    operator = operators(:cowork_tahoe)
    other_location = create(:location, operator: operator)
    visit new_post_path
    fill_in "Title", with: "Test Post Title"
    find('trix-editor').click.set('Test Post Content')
    click_on "Post"

    assert_text "Test Post Title"
    assert_text "Test Post Content"

    # user sees post at the location
    visit home_path
    assert_text "Test Post Title"

    # admin sees the post in the list
    visit posts_path
    assert_text "Test Post Title"

    # change location
    switch_to_location(other_location)

    # user sees no post at the other location
    visit home_path
    assert_no_text "Test Post Title"

    # admin sees no post in the list at the other location
    visit posts_path
    assert_no_text "Test Post Title"
  end
end