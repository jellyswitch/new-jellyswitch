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
    # QUARANTINED (stale, tracked in SYSTEM_TEST_CLEANUP.md): drives the real
    # Stripe Elements card form via find("iframe[name^='__privateStripeFrame']").
    # That iframe only exists once Stripe.js loads from js.stripe.com, which the
    # test WebMock config blocks (allow-list is chromedriver/storage/fcm only) —
    # so it can't render here or in CI. Needs a rewrite that stubs Stripe Elements
    # or swaps to a card-token path that doesn't depend on the live iframe.
    skip "Depends on live Stripe Elements iframe (js.stripe.com is network-blocked in tests)"
    operator = operators(:cowork_tahoe)
    other_location = create(:location, operator: operator, name: "Other Location", allow_hourly: true, hourly_rate_in_cents: 500, working_day_start: "00:00", working_day_end: "23:59", open_saturday: true, open_sunday: true)
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

    # setTimeout(50) mimics real Stripe network latency so the event loop
    # drains between the user-click submit (which preventDefault'd) and
    # the followup form.requestSubmit(). With Promise.resolve()'s
    # synchronous microtask resolution, Turbo's submit listener drops the
    # programmatic second submit and the form never POSTs.
    page.execute_script(<<~JS)
      Object.defineProperty(window.stripe, 'createToken', {
        value: function(element) {
          return new Promise(function(resolve) {
            setTimeout(function() {
              resolve({ token: { id: '#{mock_token}' } });
            }, 50);
          });
        },
        writable: true,
        configurable: true
      });
    JS

    find("#stripe-submit").click

    assert_text "You're checked in", wait: 15

    # advances 2 hours
    Timecop.travel(Time.current + 2.hours)

    # reload page
    visit home_path

    assert_text "You're checked in (for about 2 hours)."

    click_on "Check out"

    assert_text "You've checked out."
  end
end