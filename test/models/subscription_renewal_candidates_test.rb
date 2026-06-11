require "test_helper"

class SubscriptionRenewalCandidatesTest < ActiveSupport::TestCase
  setup do
    @operator = operators(:cowork_tahoe)
    ActsAsTenant.current_tenant = @operator
    @subscription = subscriptions(:cowork_tahoe_subscription) # active: true, not cancelling
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  test "includes active subscriptions that are not scheduled to cancel" do
    assert_includes Subscription.renewal_reminder_candidates, @subscription
  end

  test "excludes subscriptions scheduled to cancel at end of billing period" do
    @subscription.update!(cancelling_at_end_of_billing_period: true)
    assert_not_includes Subscription.renewal_reminder_candidates, @subscription
  end

  test "excludes inactive subscriptions" do
    @subscription.update!(active: false)
    assert_not_includes Subscription.renewal_reminder_candidates, @subscription
  end
end
