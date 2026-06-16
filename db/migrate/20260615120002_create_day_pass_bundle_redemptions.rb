class CreateDayPassBundleRedemptions < ActiveRecord::Migration[7.1]
  def change
    create_table :day_pass_bundle_redemptions do |t|
      t.references :day_pass_bundle, null: false
      t.bigint :operator_id, null: false, default: 1
      t.string :kind, null: false
      t.references :performed_by, foreign_key: { to_table: :users }
      t.references :day_pass
      t.string :guest_name
      t.datetime :redeemed_at, null: false
      t.timestamps
    end
  end
end
