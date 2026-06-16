class CreateDayPassBundles < ActiveRecord::Migration[7.1]
  def change
    create_table :day_pass_bundles do |t|
      t.references :user, null: false
      t.references :day_pass_type, null: false
      t.references :location
      t.bigint :operator_id, null: false, default: 1
      t.string :billable_type
      t.bigint :billable_id
      t.integer :quantity_purchased, null: false
      t.integer :passes_remaining, null: false
      t.datetime :expires_at
      t.datetime :purchased_at, null: false
      t.references :invoice
      t.timestamps
    end
    add_index :day_pass_bundles, [:billable_type, :billable_id]
    add_index :day_pass_bundles, :operator_id
  end
end
