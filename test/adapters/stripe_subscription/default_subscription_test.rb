require "test_helper"

class StripeSubscription::DefaultSubscriptionTest < ActiveSupport::TestCase
  setup do
    @location = locations(:cowork_tahoe_location)
    @sub = subscriptions(:cowork_tahoe_subscription)
  end

  def adapter(lease: nil)
    StripeSubscription::DefaultSubscription.new(@sub, @location, lease)
  end

  # A Commitment is a MINIMUM term on an ONGOING subscription — it must not set
  # Stripe cancel_at, which would auto-end the membership when the term is up
  # (the original bug). Early-cancel enforcement lives in the cancel flow.
  test "a committed (non-lease) subscription has no cancel_at — it is ongoing" do
    @sub.plan.update!(interval: "monthly", commitment_interval: 6, plan_type: "individual")
    assert_nil adapter.cancel_at,
      "commitment must NOT auto-cancel the membership at the term boundary"
  end

  test "a non-committed subscription also has no cancel_at" do
    @sub.plan.update!(commitment_interval: nil, plan_type: "individual")
    assert_nil adapter.cancel_at
  end
end
