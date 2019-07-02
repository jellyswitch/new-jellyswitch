# typed: true
module StripeSubscription
  class InBandDefaultStartDay < DefaultSubscription
    def subscription_args
      super.merge!(billing: 'charge_automatically')
    end
  end
end