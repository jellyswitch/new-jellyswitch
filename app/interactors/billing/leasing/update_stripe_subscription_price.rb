class Billing::Leasing::UpdateStripeSubscriptionPrice
  include Interactor

  delegate :office_lease, :new_price_in_cents, :operator, to: :context

  def call
    subscription = office_lease.subscription

    stripe_subscription = office_lease.location.update_stripe_subscription_price(subscription, new_price_in_cents)
    context.updated_stripe_subscription = stripe_subscription
  rescue StandardError => e
    context.fail!(message: "Failed to update Stripe subscription: #{e.message}")
  end
end
