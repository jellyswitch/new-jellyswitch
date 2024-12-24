require 'application_system_test_case'

class DayPassAccessTest < ApplicationSystemTestCase
  setup do
    StripeMock.start

    @user = users(:cowork_tahoe_non_member)
    setup_stripe_no_subscription
  end

  teardown do
    StripeMock.stop
  end

  test "user accesses a location via its daypass" do
    log_in(users(:cowork_tahoe_non_member))
    operator = operators(:cowork_tahoe)
    other_location = create(:location, operator: operator)
    visit home_path

    assert_text "Please select an option below."

    click_on "Buy a day pass"
    click_on "Select Standard Day Pass"

    assert_text "$200"

    click_on "Confirm and purchase"

    assert_text "Building Access"

    # change location
    switch_to_location(other_location)

    assert_no_text "Building Access"
    assert_text "Please select an option below."
  end

  test "user registers at one location then purchases daypass at another" do
    log_in(users(:cowork_tahoe_non_member))
    operator = operators(:cowork_tahoe)
    first_location = operator.locations.first
    second_location = create(:location, operator: operator, name: "Second Location")

    # Set up day pass type for second location matching the YAML structure
    second_location_day_pass = DayPassType.create!(
      name: "Standard Day Pass",
      operator: operator,
      location: second_location,
      amount_in_cents: 20000,  # $200
      available: true,
      visible: true,
      always_allow_building_access: false,
      code: ""
    )

    # Start at first location
    visit home_path
    assert_text "Please select an option below."

    # Switch to second location
    switch_to_location(second_location)
    assert_text "Please select an option below."

    # Purchase day pass at second location
    click_on "Buy a day pass"
    click_on "Select Standard Day Pass"
    assert_text "$200"

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

    click_on "Confirm and purchase"

    # Verify access granted for second location
    assert_text "Building Access"

    # Verify no access at first location
    switch_to_location(first_location)
    assert_no_text "Building Access"
    assert_text "Please select an option below."
  end
end