
module StripeSubscription
  class DefaultSubscription < SimpleDelegator
    attr_accessor :subscription, :lease, :location

    def initialize(subscription, location, lease)
      @subscription = subscription
      @location = location
      @lease = lease
    end

    def subscription_args
      {
        customer: subscription.billable.stripe_customer_id_for_location(location),
        items: [{ plan: subscription.plan.stripe_plan_id }],
        prorate: false,
        billing_cycle_anchor: billing_cycle_anchor,
        cancel_at: cancel_at
      }
    end

    def billing_cycle_anchor
      if subscription.plan.plan_type == "lease"
        if lease.present?
          if lease.initial_invoice_date > Time.zone.now
            lease.initial_invoice_date.to_time.to_i + 2.hours
          else
            nil # now
          end
        else
          nil # today
        end
      else
        if subscription.start_date == Time.zone.today
          nil # today
        else
          subscription.start_date.in_time_zone.to_i + 2.hours
        end
      end
    end

    def cancel_at
      # Only a fixed-end LEASE gets a Stripe cancel_at. A Commitment is a
      # minimum term on an ONGOING subscription — it must NOT auto-cancel at the
      # term boundary (that was the original bug, see ADR 0005). Early-cancel
      # enforcement during a commitment lives in the cancel flow instead.
      return nil unless subscription.plan.plan_type == "lease"
      lease&.end_date&.to_time&.to_i
    end
  end
end
