class AssignBillingContactToOrganizations < ActiveRecord::Migration[7.0]
  def change
    Organization.all.map { |organization| organization.update(billing_contact: organization.owner) }
  end
end
