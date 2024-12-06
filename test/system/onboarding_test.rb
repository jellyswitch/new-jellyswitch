require 'application_system_test_case'
require 'uri'
require 'cgi'

class OnboardingTest < ApplicationSystemTestCase
  setup do
    @original_app_host = Capybara.app_host
    Capybara.app_host = "http://app.lvh.me"
    stub_request(:post, "https://connect.stripe.com/oauth/token")
      .with(query: hash_including({}))
      .to_return(
        status: 200,
        body: {
          stripe_user_id: "acct_123456",
          stripe_publishable_key: "pk_test_123456",
          refresh_token: "rt_123456",
          access_token: "sk_test_123456"
        }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )

    stub_request(:post, "https://api.stripe.com/v1/customers")
      .to_return(
        status: 200,
        body: {id: "user123"}.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end

  teardown do
    Capybara.app_host = @original_app_host
    WebMock.reset!
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

    # check if user is approved
    assert Operator.last.users.last.approved?

    # simulate already set up stripe
    Operator.last.update(billing_state: "production")
    click_on "Take me to my Jellyswitch"

    # setup billing
    mock_response = {
      "stripe_user_id" => "acct_123456",
      "stripe_publishable_key" => "pk_test_123456",
      "refresh_token" => "rt_123456",
      "access_token" => "sk_test_123456"
    }

    click_on "Enable billing & payments"
    link = find_link("I already have a Stripe account")
    uri = URI.parse(link[:href])
    params = CGI.parse(uri.query)
    visit params["redirect_uri"][0]

    assert_text "Your location has been connected to Stripe"

    # setup building access / kisi
    find(".kisi-setup").click
    fill_in "Paste your Kisi API key here", with: "KISI1"
    click_on "Next"

    # for some reason the test is too fast and the location is not updated yet
    wait_for do
      Location.last.kisi_api_key == "KISI1"
    end

    # setup rooms
    Capybara.app_host = "http://operator-company.lvh.me"
    visit feed_items_path
    click_on "Reservable rooms"

    assert_text "What is this room called?"
    fill_in "Conference Room", with: "Test Room 1"
    fill_in "Description", with: "Test room for reservation"
    fill_in "How big is this room (sq ft)?", with: "100"
    fill_in "room[hourly_rate_in_cents]", with: "1000"
    click_on "+ Add More"
    fill_in "Name", with: "Whiteboard"
    click_on "Just add this room"

    assert_text "Room added."
    assert_no_text "Reservable rooms"

    # assert room appearance
    visit home_path
    assert_text "Reserve a meeting room"

    other_location = create(:location, operator: Operator.last)

    switch_to_location other_location
    visit home_path
    assert_no_text "Reserve a meeting room"

    visit edit_location_path(other_location)
    fill_in "location[kisi_api_key]", with: "New KISI key"
    click_on "Update"
    assert_text "Location updated."
    assert_text "New KISI key"
  end
end