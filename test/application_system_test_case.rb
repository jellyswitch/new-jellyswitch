require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [1400, 1400]

  setup do
    Capybara.app_host = "http://tml.lvh.me"
    Capybara.server_port = 9000
  end

  def log_in(user)
    user.update(password: "password")
    visit login_path
    sleep 1

    fill_in "Email", with: user.email
    fill_in "Password", with: "password"

    find("#sign-in").click
  end

  def wait_for_ajax
    Timeout.timeout(Capybara.default_max_wait_time) do
      loop until finished_all_ajax_requests?
    end
  end

  def finished_all_ajax_requests?
    page.evaluate_script("jQuery.active").zero?
  end
end
