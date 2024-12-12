
class SaveOrganization
  include Interactor

  delegate :organization, :operator, :location, to: :context

  def call
    organization.location = location

    if organization.save
      context.billable = organization
    else
      context.fail!(message: 'Could not save organization.')
    end
  end

  def rollback
    context.organization.destroy
  end
end
