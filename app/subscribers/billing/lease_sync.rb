class Billing::LeaseSync
  def self.call(office_lease_id:, operator_id:)
    operator = Operator.find(operator_id)
    lease = OfficeLease.find(office_lease_id)
    organization = lease.organization
    subscription = organization.subscription
    start_date = (Time.zone.at(lease.start_date.to_time.to_i) + 2.hours).to_i

    operator.create_stripe_subscription(organization, subscription, start_date)
  end
end
