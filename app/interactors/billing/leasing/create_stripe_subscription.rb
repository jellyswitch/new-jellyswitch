class Billing::Leasing::CreateStripeSubscription
  include Interactor

  delegate :office_lease, :operator, to: :context

  def call
    subscription = office_lease.subscription
    organization = subscription.subscribable
    start_date = office_lease.start_date

    if start_date < Time.current
      stripe_start_date = Time.zone.at(1.month.from_now.beginning_of_month + 2.hours).to_i
    else
      stripe_start_date = (Time.zone.at(start_date.to_time.to_i) + 2.hours).to_i
    end

    stripe_subscription = operator.create_stripe_subscription(organization, subscription, stripe_start_date)
    subscription.update(stripe_subscription_id: stripe_subscription.id)
  end
end
