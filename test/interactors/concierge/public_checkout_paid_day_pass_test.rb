require "stripe_mock"
require "test_helper"

# End-to-end coverage for the anonymous concierge PAID day-pass purchase
# (Embed::ConciergeController#purchase, no login — the most public purchase
# path in the app).
#
# Why this exists: Billing::DayPasses::UpdatePaymentAndCreateDayPass runs
# SaveDayPass BEFORE Billing::Payment::UpdateUserPayment, and SaveDayPass
# refuses a paid pass unless the billable already has a Stripe customer for
# the location. That ordering is safe from the concierge only because
# account creation (Users::Save → CreateStripeCustomer) stamps a Stripe
# customer onto the new user's payment profile for original_location — which
# Concierge::PublicCheckout sets to the purchase location — before the
# billing organizer is invoked. These tests pin both the end-to-end outcome
# and that load-bearing wiring.
class Concierge::PublicCheckoutPaidDayPassTest < ActiveSupport::TestCase
  setup do
    StripeMock.start
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
  end

  teardown do
    StripeMock.stop
  end

  def checkout_args(day_pass_type, token:)
    {
      operator: @operator, location: @location, day_pass_type: day_pass_type, day: Date.current + 1,
      email: "widget.visitor@example.com", name: "Widget Visitor", password: "sup3rsecret",
      phone: "555-0100", terms_accepted: "1", token: token,
    }
  end

  def create_paid_type
    DayPassType.create!(operator: @operator, location: @location, name: "Day Pass",
                        amount_in_cents: 2_500, quantity: 1, available: true, visible: true)
  end

  test "first-time anonymous paid purchase creates the account, charges the card, and issues the pass" do
    result = nil

    ActsAsTenant.with_tenant(@operator) do
      day_pass_type = create_paid_type
      token = StripeMock.create_test_helper.generate_card_token

      assert_difference -> { User.count } => 1, -> { DayPass.count } => 1, -> { Invoice.count } => 1 do
        result = Concierge::PublicCheckout.call(checkout_args(day_pass_type, token: token))
      end
    end

    assert result.success?, "expected checkout to succeed, got: #{result.message}"

    day_pass = result.day_pass
    assert day_pass.persisted?
    # No amount assertion: StripeMock invoices don't sum pending invoice items
    # (amount_due comes back as the mock's default), so the charged total here
    # would only pin mock behavior.
    assert_equal "paid", day_pass.invoice.status

    user = result.user
    assert_equal day_pass.user, user
    assert user.card_added_for_location?(@location), "card token should be attached to the new customer"
  end

  test "the new user already has a Stripe customer for the purchase location when the billing organizer starts" do
    result = nil
    probed = false

    # Halt at the organizer boundary and inspect the user as SaveDayPass would
    # find them. Read the payment profile directly — has_stripe_customer_for_location?
    # lazily creates a customer on first read, which would mask a regression.
    probe = ->(ctx) {
      user = User.find(ctx[:user_id])
      profile = user.user_payment_profiles.find_by(location: ctx[:location])
      assert profile&.stripe_customer_id.present?,
             "signup must pre-create the Stripe customer for the purchase location " \
             "(SaveDayPass runs before UpdateUserPayment and rejects users without one)"
      probed = true

      Interactor::Context.build(message: "probe halt").tap do |halt|
        halt.fail!
      rescue Interactor::Failure
        # fail! raises; we only want the failed context back
      end
    }

    ActsAsTenant.with_tenant(@operator) do
      day_pass_type = create_paid_type
      token = StripeMock.create_test_helper.generate_card_token

      Billing::DayPasses::UpdatePaymentAndCreateDayPass.stub :call, probe do
        result = Concierge::PublicCheckout.call(checkout_args(day_pass_type, token: token))
      end
    end

    assert probed, "checkout never reached the billing organizer"
    assert result.failure?
    assert_equal "payment", result.error
  end
end
