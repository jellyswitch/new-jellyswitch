class AllowUserBasedOfficeLeases < ActiveRecord::Migration[7.1]
  def change
    add_reference :office_leases, :user, foreign_key: true, null: true
    change_column_null :office_leases, :organization_id, true
    add_column :office_leases, :deposit_amount_in_cents, :integer, default: 0, null: false
  end
end
