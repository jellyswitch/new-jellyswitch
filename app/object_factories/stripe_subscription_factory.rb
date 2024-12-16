
class StripeSubscriptionFactory
  def self.for(subscription, location, lease)
    if subscription.billable.out_of_band?
      StripeSubscription::OutOfBand
    else
      StripeSubscription::InBand
    end.new(subscription, location, lease)
  end
end