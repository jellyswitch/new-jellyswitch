require "test_helper"

# Viewing a profile whose billable has NO Stripe customer must not 500.
# stripe-ruby raises client-side on Customer.retrieve(nil) ("Could not
# determine which URL to request … invalid ID: nil") before any network
# call — hit live 2026-07-29 by a TLH admin opening his own profile
# (operator/users#show self-view → _payment_method_user →
# card_last_4_digits → Location#retrieve_stripe_customer(nil id)) after
# the 7/17 cleanup nulled admin payment profiles.
class Operator::UsersShowStripeNilTest < ActionDispatch::IntegrationTest
  setup do
    setup_initial_user_fixtures
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @admin    = users(:cowork_tahoe_admin)
    host! "#{@operator.subdomain}.example.com"

    # Force the incident shape: a payment profile with card_added set (so
    # the card branch of _payment_method_user renders) but NO Stripe
    # customer id behind it.
    profile = @admin.payment_profile_for_location(@location)
    if profile
      profile.update!(stripe_customer_id: nil, card_added: true)
    end
  end

  test "retrieve_stripe_customer returns nil for a billable with no stripe id" do
    assert_nil @admin.stripe_customer_id_for_location(@location)
    assert_nil @location.retrieve_stripe_customer(@admin)
  end

  test "own profile page renders despite the missing stripe customer" do
    log_in @admin
    get user_path(@admin), env: default_env
    assert_response :success
  end
end
