require 'application_system_test_case'

class AuthenticationTest < ApplicationSystemTestCase
  setup do
    StripeMock.start
  end

  test 'logging in as an admin' do
    user = users(:cowork_tahoe_admin)

    log_in(user)
    assert_text "What's Happening?"
  end

  test 'logging out as a member' do
    @user = users(:cowork_tahoe_member)
    setup_stripe
    log_in(@user)
    # Navigate directly to the user profile page where Log out is a visible
    # button (operator/users/show.html.erb); the nav dropdown's Log out item
    # is hidden until the dropdown is opened.
    visit user_path(@user)

    click_on 'Log out'
    assert_text operators(:cowork_tahoe).snippet
  end
end