require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [1400, 1400]

  setup do
    Capybara.app_host = "http://tml.lvh.me"
    Capybara.server_port = nil
  end

  def log_in(user)
    user.update(password: "password")
    visit login_path

    assert_text("Welcome back to Cowork Tahoe!")

    fill_in "Email", with: user.email
    fill_in "Password", with: "password"

    find("#sign-in").click
    wait_for_turbo
  end

  def wait_for
    Timeout.timeout(Capybara.default_max_wait_time) do
      loop until yield
    end
  end

  def wait_for_ajax
    Timeout.timeout(Capybara.default_max_wait_time) do
      loop until finished_all_ajax_requests?
    end
  end

  def switch_to_location(location)
    visit root_path
    if page.has_link?("Change Location")
      click_on "Change Location"
    else
      find(".navbar-toggler").click
      click_on "Change Location"
    end
    page.find_button(location.name).click
    wait_for_turbo
  end

  def wait_for_turbo
    has_css?("html.turbo-progress-bar", wait: 2)
    has_no_css?("html.turbo-progress-bar", wait: 2)
  end

  def finished_all_ajax_requests?
    page.evaluate_script("jQuery.active").zero?
  end

  def with_sidekiq_inline
    original_mode = Sidekiq::Testing.disabled? ? :disable : (Sidekiq::Testing.fake? ? :fake : :inline)
    Sidekiq::Testing.inline!
    yield
  ensure
    case original_mode
    when :disable
      Sidekiq::Testing.disable!
    when :fake
      Sidekiq::Testing.fake!
    when :inline
      Sidekiq::Testing.inline!
    end
  end
end
