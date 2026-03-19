class CreateDiscountRedemptions < ActiveRecord::Migration[7.1]
  def change
    create_table :discount_redemptions do |t|
      t.references :discount_code, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :discountable_type
      t.bigint :discountable_id
      t.integer :discount_amount_in_cents, null: false
      t.integer :operator_id, null: false

      t.timestamps
    end

    add_index :discount_redemptions, [:discountable_type, :discountable_id], name: "index_discount_redemptions_on_discountable"
    add_index :discount_redemptions, :operator_id
  end
end
