class CreateOfficeLease
  include Interactor

  delegate :office_lease, :operator, to: :context

  def call
    organization = Organization.find(office_lease.organization_id)
    subscription = office_lease.subscription
    subscription.subscribable = organization

    unless office_lease.end_date
      office_lease.end_date = office_lease.start_date + 1.year
    end

    if office_lease.save
      Jellyswitch::Events.publish(
        'billing.lease.create',
        office_lease_id: office_lease.id,
        operator_id: operator.id,
        start_date: office_lease.start_date
      )
    else
      context.fail!(message: 'Could not create lease')
    end
  end
end
