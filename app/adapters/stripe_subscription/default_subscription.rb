# typed: true
module StripeSubscription
  class DefaultSubscription < SimpleDelegator
    attr_accessor :subscription

    def initialize(subscription)
      @subscription = subscription
    end

    def subscription_args
      {
        customer: subscription.billable.stripe_customer_id,
        items: [{ plan: subscription.plan.stripe_plan_id }],
        prorate: false,
        billing_cycle_anchor: subscription.start_date.to_time.to_i
      }
    end
  end
end