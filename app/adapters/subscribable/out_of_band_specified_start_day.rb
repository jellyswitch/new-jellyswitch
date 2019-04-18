module Subscribable
  class OutOfBandSpecifiedStartDay < DefaultSubscription
    def subscription_args
      super.merge!(
        billing: 'send_invoice',
        billing_cycle_anchor: start_day.to_i,
        days_until_due: 30,
      )
    end
  end
end