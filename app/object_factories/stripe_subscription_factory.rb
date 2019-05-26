class StripeSubscriptionFactory
  def self.for(subscription, start_day)
    if subscription.billable.out_of_band?
      if start_day.present?
        StripeSubscription::OutOfBandSpecifiedStartDay
      else
        StripeSubscription::OutOfBandDefaultStartDay
      end
    else
      if start_day.present?
        StripeSubscription::InBandSpecifiedStartDay
      else
        StripeSubscription::InBandDefaultStartDay
      end
    end.new(subscription, start_day)
  end
end