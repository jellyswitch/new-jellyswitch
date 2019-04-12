class Billing::LeaseSync
  def self.call(office_lease_id:, operator_id:, start_date:)
    office_lease = OfficeLease.find(office_lease_id)
    subscription = office_lease.subscription
    organization = subscription.subscribable
    operator = Operator.find(operator_id)
    start_date = (Time.zone.at(start_date.to_time.to_i) + 2.hours).to_i

    stripe_subscription = operator.create_stripe_subscription(organization, subscription, start_date)

    if stripe_subscription
      subscription.update(stripe_subscription_id: stripe_subscription.id)
    end
  end
end
