module Subscribable
  class DefaultSubscription < SimpleDelegator
    attr_accessor :subscriber, :subscription, :start_day

    def initialize(subscriber, subscription, start_day)
      @subscriber = subscriber
      @subscription = subscription
      @start_day = start_day
    end

    def subscription_args
      {
        customer: subscriber.stripe_customer_id,
        items: [{ plan: subscription.plan.stripe_plan_id }],
        prorate: false
      }
    end
  end
end