require 'application_system_test_case'

class OnboardingTest < ApplicationSystemTestCase
  setup do
    @original_app_host = Capybara.app_host
    Capybara.app_host = "http://app.lvh.me"
  end

  teardown do
    Capybara.app_host = @original_app_host
  end

  test "an operator signs up and goes through the whole flow" do
    ENV['KISI_TEST_MODE'] = 'stub'

    visit operator_signup_path

    fill_in "Enter your email address", with: "new_operator@email.com"
    click_on "Begin onboarding"

    assert_text "Just a couple things to make your app beautiful..."

    fill_in "Your company name", with: "Operator company"
    fill_in "Your name", with: "Operator Name"
    fill_in "Create a password here...", with: "password"
    fill_in "Your phone number (optional)", with: "123"
    click_on "Next"

    assert_text "Do you have any events scheduled?"
    click_on "Skip this step"

    assert_text "Which of these tasks do you perform every day?"
    click_on "Next"

    assert_text "What is your favorite part of your space?"
    find("#favorite_part_amenities").click
    click_on "Next"

    assert_text "That's it!"

    # simulate already set up stripe
    Operator.last.update(billing_state: "production")
    click_on "Take me to my Jellyswitch"

    # setup building access / kisi
    find(".kisi-setup").click
    fill_in "Paste your Kisi API key here", with: "KISI1"
    click_on "Next"

    # for some reason the test is too fast and the location is not updated yet
    wait_for do
      Location.last.kisi_api_key == "KISI1"
    end
  end
end