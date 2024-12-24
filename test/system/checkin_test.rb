require 'application_system_test_case'

class CheckinTest < ApplicationSystemTestCase
  setup do
    Timecop.travel(Time.zone.today.change(hour: 11))
    StripeMock.start

    @user = users(:cowork_tahoe_non_member)
    setup_stripe_no_subscription
  end

  teardown do
    StripeMock.stop
    Timecop.return
  end

  test "user accesses a location via its checkin" do
    operator = operators(:cowork_tahoe)
    other_location = create(:location, operator: operator, name: "Other Location", allow_hourly: true, hourly_rate_in_cents: 500, working_day_start: "00:00", working_day_end: "23:59")
    switch_to_location(other_location)
    log_in(@user)
    visit home_path

    assert_text "Please select an option below."
    assert_text "Pay as you go"

    click_on "Check in now"

    assert_text "Other Location costs $5.00 / hr. You will be billed automatically after you check out."

    # Switch to Stripe iframe and fill in test card
    stripe_iframe = find("iframe[name^='__privateStripeFrame']")
    within_frame(stripe_iframe) do
      # Fill in test card number - using Stripe's test card
      find_field('cardnumber').fill_in with: '4242424242424242'

      # The expiry and CVC fields become visible after card number
      find_field('exp-date').fill_in with: '1234' # This will format as 12/34
      find_field('cvc').fill_in with: '123'
      find_field('postal').fill_in with: '12345'
    end

    mock_token = StripeMock.generate_card_token(last4: "4242", exp_month: 12, exp_year: 34)
    p "Mock token: #{mock_token}"

    page.execute_script(<<~JS)
      Object.defineProperty(window.stripe, 'createToken', {
        value: function(element) {
          return Promise.resolve({
            token: {
              id: '#{mock_token}'
            }
          });
        },
        writable: true,
        configurable: true
      });
    JS

    click_on "Check in now"

    assert_text "You're checked in"

    # advances 2 hours
    Timecop.travel(Time.current + 2.hours)

    # reload page
    visit home_path

    assert_text "You're checked in (for about 2 hours)."

    click_on "Check out"

    assert_text "You've checked out."
  end
end