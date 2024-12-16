module SystemTestHelper
  def log_in(user)
    user.reload.update(password: "password")
    visit login_path

    expect(page).to have_content("Welcome back to Cowork Tahoe!")

    fill_in "Email", with: user.email
    fill_in "Password", with: "password"

    find("#sign-in").click
    wait_for_turbo
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

  def wait_for_ajax
    Timeout.timeout(Capybara.default_max_wait_time) do
      loop until finished_all_ajax_requests?
    end
  end

  def wait_for_turbo
    has_css?("html.turbo-progress-bar", wait: 2)
    has_no_css?("html.turbo-progress-bar", wait: 2)
  end

  def finished_all_ajax_requests?
    page.evaluate_script("jQuery.active").zero?
  end
end
