require 'application_system_test_case'

class UserSearchTest < ApplicationSystemTestCase
  setup do
    StripeMock.start

    @admin = users(:cowork_tahoe_admin)
    @user = users(:cowork_tahoe_member)

    setup_stripe
    log_in(@admin)
    sleep 2
  end

  teardown do
    StripeMock.stop
  end

  test "performing a search" do
    visit users_path

    fill_in "query", with: @user.name
    find('button.search-btn').click

    assert_text @user.name
  end

  test "search with no results" do
    visit users_path

    fill_in "query", with: "nonexistentuser"
    find('button.search-btn').click

    assert_text "No users found."
  end
end
