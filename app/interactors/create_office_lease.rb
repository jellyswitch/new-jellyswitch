class CreateOfficeLease
  include Interactor

  delegate :office_lease, :operator, to: :context

  def call
    organization = Organization.find(office_lease.organization_id)
    plan = Plan.find(office_lease.plan_id)
    owner = organization.owner
    subscription = Subscription.new(
      plan: office_lease.plan,
      subscribable: organization
    )
    office_lease.end_date = office_lease.start_date + 1.year

    if office_lease.save && subscription.save
      Jellyswitch::Events.publish(
        'billing.lease.create',
        office_lease_id: office_lease.id,
        operator_id: operator.id
      )
    else
      context.fail!(message: 'Could not create lease')
    end
  end
end
