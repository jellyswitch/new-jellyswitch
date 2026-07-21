require 'test_helper'

class Operator::SettingsPaymentsTest < ActionDispatch::IntegrationTest
  setup do
    setup_initial_user_fixtures
    @admin    = users(:cowork_tahoe_admin)
    @operator = @admin.operator
    @location = locations(:cowork_tahoe_location)
    log_in @admin
  end

  test "GET payments renders as admin" do
    get settings_payments_path, env: default_env
    assert_response :success
  end

  # The Connect/Reconnect buttons open the shared Stripe modal via a Bootstrap
  # data-target. The partial's id had drifted (#exampleModalCenter) while the
  # buttons pointed at #stripeModal, leaving NO working way to (re)connect
  # Stripe from settings — an operator who linked the wrong Stripe account was
  # stuck. Pin the button target and the modal id to each other.
  test "payments page connect button targets a modal that exists" do
    get settings_payments_path, env: default_env

    assert_response :success
    assert_match 'data-target="#stripeModal"', response.body
    assert_match 'id="stripeModal"', response.body
  end

  # ADR 0012: the "Overage / add-on meeting room time" rate is location-scoped
  # and entered in dollars (HasDollars virtual writes overage_rate_in_cents).
  # Its form lives on the Rooms & Reservations page, so saving returns there.
  test "update_payments saves the location overage rate" do
    patch settings_update_payments_path, env: default_env, params: {
      location: { overage_rate: "12.00" },
    }

    assert_redirected_to rooms_path
    assert_equal 1200, @location.reload.overage_rate_in_cents
  end

  # The overage rate is room pricing, not a payment-processor setting — it is
  # edited from Rooms & Reservations, and the Payments tab is Stripe-only.
  test "payments page no longer carries the overage pricing form" do
    get settings_payments_path, env: default_env

    assert_response :success
    assert_no_match(/overage_rate/, response.body)
  end
end
