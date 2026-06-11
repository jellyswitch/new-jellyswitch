class AddDepositInvoicedAtToOfficeLeases < ActiveRecord::Migration[7.1]
  def change
    add_column :office_leases, :deposit_invoiced_at, :datetime, null: true
  end
end
