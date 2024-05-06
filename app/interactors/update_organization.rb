class UpdateOrganization
  include Interactor::Organizer

  organize UpdateOrganizationDetails, Billing::Organization::UpdateBillingDetails
end
