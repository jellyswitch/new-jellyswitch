class OrganizationBillDecider
  attr_accessor :organization

  def initialize(organization)
    @organization = organization
  end

  def billable
    if @organization.has_billing_contact?
      organization.billing_contact
    else
      organization
    end
  end
end