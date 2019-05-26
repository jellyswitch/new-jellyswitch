module StripeSubscription
  class InBandSpecifiedStartDay < DefaultSubscription
    def subscription_args
      super.merge!(billing: 'charge_automatically', billing_cycle_anchor: start_day.to_i)
    end
  end
end