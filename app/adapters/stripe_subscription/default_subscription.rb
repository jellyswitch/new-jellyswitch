# typed: true
module StripeSubscription
  class DefaultSubscription < SimpleDelegator
    attr_accessor :subscription, :start_day

    def initialize(subscription, start_day)
      @subscription = subscription
      @start_day = start_day
    end

    def subscription_args
      {
        customer: subscription.billable.stripe_customer_id,
        items: [{ plan: subscription.plan.stripe_plan_id }],
        prorate: false
      }
    end
  end
end