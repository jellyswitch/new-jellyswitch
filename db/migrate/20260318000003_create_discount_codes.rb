class CreateDiscountCodes < ActiveRecord::Migration[7.1]
  def change
    create_table :discount_codes do |t|
      t.string :code, null: false
      t.integer :operator_id, null: false
      t.integer :location_id
      t.string :discount_type, null: false
      t.integer :discount_value, null: false
      t.string :applies_to, null: false, default: "all"
      t.integer :max_redemptions
      t.integer :redemption_count, default: 0, null: false
      t.datetime :expires_at
      t.boolean :active, default: true, null: false
      t.string :stripe_coupon_id

      t.timestamps
    end

    add_index :discount_codes, [:operator_id, :code], unique: true
    add_index :discount_codes, [:operator_id, :location_id]
  end
end
