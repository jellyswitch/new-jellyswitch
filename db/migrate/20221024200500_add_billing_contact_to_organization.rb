class AddBillingContactToOrganization < ActiveRecord::Migration[7.0]
  def change
    add_column :organizations, :billing_contact_id, :integer
  end
end
