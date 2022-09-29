require 'application_system_test_case'

class AuthenticationTest < ApplicationSystemTestCase
  test 'logging in as an admin' do
    user = users(:cowork_tahoe_admin)

    log_in(user)
    assert_text "What's Happening?"
  end

  test 'logging out as a member' do
    user = users(:cowork_tahoe_member)
    log_in(user)
    click_on 'My Account'

    click_on 'Log out'
    assert_text operators(:cowork_tahoe).snippet
  end
end