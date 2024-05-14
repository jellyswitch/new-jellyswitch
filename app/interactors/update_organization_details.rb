class UpdateOrganizationDetails
  include Interactor

  delegate :organization, :params, to: :context

  def call
    organization.update(params)

    if organization.save
      context.organization = organization
    else
      context.fail!(message: "Failed to update organization details: #{organization.errors.full_messages.join(", ")}")
    end
  end
end
