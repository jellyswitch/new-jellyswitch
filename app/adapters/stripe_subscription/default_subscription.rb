# typed: true
module StripeSubscription
  class DefaultSubscription < SimpleDelegator
    attr_accessor :subscription, :lease

    def initialize(subscription, lease)
      @subscription = subscription
      @lease = lease
    end

    def subscription_args
      {
        customer: subscription.billable.stripe_customer_id,
        items: [{ plan: subscription.plan.stripe_plan_id }],
        prorate: false,
        billing_cycle_anchor: billing_cycle_anchor,
        cancel_at: cancel_at
      }
    end

    def billing_cycle_anchor
      if subscription.start_date == Time.zone.today
        nil
      else
        subscription.start_date.to_time.to_i
      end
    end

    def cancel_at
      if subscription.plan.plan_type == "lease"
        if lease.present?
          lease.end_date.to_time.to_i
        else
          puts "LEASE NOT PASSED"
          nil
        end
      else
        nil
      end
    end
  end
end