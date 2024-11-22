
class Billing::Leasing::CreateStripeSubscription
  include Interactor

  delegate :office_lease, :operator, to: :context

  def call
    subscription = office_lease.subscription
    organization = subscription.subscribable
    location = office_lease.location

    stripe_subscription = location.create_stripe_subscription(subscription, lease: office_lease)
    subscription.update(stripe_subscription_id: stripe_subscription.id)
  rescue StandardError => e
    context.fail!(message: e.message)
  end
end
