require 'application_system_test_case'

class AuthenticationCheckTest < ApplicationSystemTestCase
  test "logged in user can access profile" do
    user = users(:cowork_tahoe_admin)
    operator = operators(:cowork_tahoe)

    log_in(user)
    visit user_path(user)
    wait_for_ajax

    assert_text "My Account"
    assert_text "View my membership"
  end

  test "non logged in user need to login" do
    user = users(:cowork_tahoe_admin)
    operator = operators(:cowork_tahoe)

    visit user_path(user)

    assert_text "You must be logged in to access this page."
    assert_text "Sign In"
  end
end