class Billing::LeaseSync
  def self.call(office_lease_id:, operator_id:, start_date:)
    office_lease = OfficeLease.find(office_lease_id)
    subscription = office_lease.subscription
    organization = subscription.subscribable
    operator = Operator.find(operator_id)

    if start_date < Time.current
      stripe_start_date = Time.zone.at(1.month.from_now.beginning_of_month + 2.hours).to_i
    else
      stripe_start_date = (Time.zone.at(start_date.to_time.to_i) + 2.hours).to_i
    end
    puts "STRIPE START DATE"
    puts stripe_start_date.inspect
    stripe_subscription = operator.create_stripe_subscription(organization, subscription, stripe_start_date)
    subscription.update(stripe_subscription_id: stripe_subscription.id)
  end
end
