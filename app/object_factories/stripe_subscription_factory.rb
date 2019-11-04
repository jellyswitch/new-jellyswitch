# typed: true
class StripeSubscriptionFactory
  def self.for(subscription)
    if subscription.billable.out_of_band?
      StripeSubscription::OutOfBand
    else
      StripeSubscription::InBand
    end.new(subscription)
  end
end