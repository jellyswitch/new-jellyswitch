class Billing::Leasing::CreateStripeSubscription
  include Interactor

  delegate :office_lease, :operator, to: :context

  def call
    subscription = office_lease.subscription
    organization = subscription.subscribable
    initial_invoice_date = office_lease.initial_invoice_date

    stripe_start_date = (Time.zone.at(initial_invoice_date.to_time.to_i) + 2.hours).to_i

    stripe_subscription = operator.create_stripe_subscription(organization, subscription, stripe_start_date)
    subscription.update(stripe_subscription_id: stripe_subscription.id)
  rescue StandardError => e
    context.fail!(message: e.message)
  end
end
