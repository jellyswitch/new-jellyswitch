# typed: true
class Billing::Leasing::CreateStripeSubscription
  include Interactor

  delegate :office_lease, :operator, to: :context

  def call
    subscription = office_lease.subscription
    organization = subscription.subscribable
    initial_invoice_date = office_lease.initial_invoice_date

    stripe_start_date = (Time.zone.at(initial_invoice_date.end_of_day.to_time.to_i)).to_i

    stripe_subscription = operator.create_stripe_subscription(subscription, lease: office_lease)
    subscription.update(stripe_subscription_id: stripe_subscription.id)
  rescue StandardError => e
    context.fail!(message: e.message)
  end
end
