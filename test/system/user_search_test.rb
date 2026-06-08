require 'application_system_test_case'

class UserSearchTest < ApplicationSystemTestCase
  setup do
    StripeMock.start

    @admin = users(:cowork_tahoe_admin)
    @user = users(:cowork_tahoe_member)

    setup_stripe
    log_in(@admin)
    User.reindex
    sleep 2
  end

  teardown do
    StripeMock.stop
  end

  test "performing a search" do
    visit users_path

    # The search box is now a button-less GET form that submits on Enter
    # (posts to search_users_path).
    fill_in("query", with: @user.name).send_keys(:return)

    assert_text @user.name
  end

  test "search with no results" do
    visit users_path

    fill_in("query", with: "nonexistentuser").send_keys(:return)

    assert_text 'No members match "nonexistentuser"'
  end
end
