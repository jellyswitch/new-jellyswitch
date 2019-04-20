class Billing::Subscription::CreateStripeSubscription
  include Interactor
  delegate :subscription, :operator, :start_day, to: :context

  def call
    user = subscription.subscribable
    stripe_subscription = operator.create_stripe_subscription(user, subscription, start_day)

    if subscription.update(stripe_subscription_id: stripe_subscription.id)
      context.notifiable = subscription
    end
  end
end
