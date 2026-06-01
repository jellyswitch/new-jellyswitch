
class StripeSubscriptionFactory
  def self.for(subscription, location, lease)
    # For an org lease, `billable` resolves to the billing-contact user, so an
    # out-of-band org with an in-band contact would otherwise be auto-charged.
    # Honor the subscribable's (org/user) out_of_band flag too.
    if subscription.billable.out_of_band? || subscription.subscribable.out_of_band?
      StripeSubscription::OutOfBand
    else
      StripeSubscription::InBand
    end.new(subscription, location, lease)
  end
end