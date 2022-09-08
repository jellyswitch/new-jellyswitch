require 'application_system_test_case'

class AuthenticationTest < ApplicationSystemTestCase
  test 'logging in as an admin' do
    Capybara.app_host = "http://tml.lvh.me"

    user = users(:cowork_tahoe_admin)
    login(user)
    assert_text "What's Happening?"
  end
end