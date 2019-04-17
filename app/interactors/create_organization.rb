class CreateOrganization
  include Interactor

  delegate :organization, to: :context

  def call
    if organization.save
      Jellyswitch::Events.publish(
        'billing.customer.create',
        billable_type: 'Organization',
        billable_id: organization.id
      )
    else
      context.fail!(message: 'Could not save organization.')
    end
  end
end
