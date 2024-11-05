class AddLocationIdToPlansAndInvoices < ActiveRecord::Migration[7.0]
  def change
    add_column :plans, :location_id, :integer
    add_index :plans, :location_id

    add_column :invoices, :location_id, :integer
    add_index :invoices, :location_id
  end
end
