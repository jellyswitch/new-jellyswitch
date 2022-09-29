require 'test_helper'

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [1400, 1400]

  setup do
    Capybara.app_host = "http://tml.lvh.me"
    Capybara.server_port = 9000
  end

  def log_in(user)
    user.update(password: 'password')
    visit login_path

    fill_in 'Email', with: user.email
    fill_in 'Password', with: 'password'

    find('#sign-in').click
  end
end
