require 'application_system_test_case'

class AuthenticationTest < ApplicationSystemTestCase
  test 'logging in as an admin' do
    Capybara.app_host = "http://tml.lvh.me"

    user = users(:cowork_tahoe_admin)
    user.update(password: 'password')

    visit login_path

    fill_in 'Email', with: user.email
    fill_in 'Password', with: 'password'

    find('#sign-in').click

    assert_text "What's Happening?"
  end
end