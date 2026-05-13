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

    page.execute_script(<<~JS)
      window.__diagErrors = [];
      window.__diagFetches = [];
      window.__diagSubmits = 0;
      window.addEventListener('error', function(e) { window.__diagErrors.push(e.message + ' @ ' + e.filename + ':' + e.lineno); });
      var origFetch = window.fetch;
      window.fetch = function() {
        var url = String(arguments[0]);
        var method = arguments[1] && arguments[1].method;
        window.__diagFetches.push([url, method, 'pending']);
        var idx = window.__diagFetches.length - 1;
        return origFetch.apply(this, arguments).then(function(r) {
          window.__diagFetches[idx] = [url, method, r.status];
          return r;
        }).catch(function(e) {
          window.__diagFetches[idx] = [url, method, 'err: ' + e.message];
          throw e;
        });
      };
      document.getElementById('stripe-form').addEventListener('submit', function() { window.__diagSubmits += 1; }, true);
    JS

    find("#stripe-submit").click

    sleep 3
    puts "[diag] URL: #{current_url}"
    puts "[diag] submit events: #{page.evaluate_script("window.__diagSubmits")}"
    puts "[diag] errors: #{page.evaluate_script("JSON.stringify(window.__diagErrors || [])")}"
    puts "[diag] fetches: #{page.evaluate_script("JSON.stringify(window.__diagFetches || [])")}"

    assert_text "You're checked in", wait: 10

    # advances 2 hours
    Timecop.travel(Time.current + 2.hours)

    # reload page
    visit home_path

    assert_text "You're checked in (for about 2 hours)."

    click_on "Check out"

    assert_text "You've checked out."
  end
end