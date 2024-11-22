
class Billing::SubscriptionSync
  def self.call(subscription_id:, start_date: nil)
    subscription = Subscription.find(subscription_id)
    user = subscription.subscribable
    operator = user.operator

    # Should be location.create_stripe_subscription but we don't have location, and also this is not used anymore
    stripe_subscription = operator.create_stripe_subscription(user, subscription, start_date)

    if stripe_subscription
      subscription.stripe_subscription_id = stripe_subscription.id
      subscription.save!
    end
  end
end
