class UpdateOrganization
  include Interactor::Organizer

  organize UpdateOrganizationDetails, Billing::Organization::UpdateBillingOwner
end
