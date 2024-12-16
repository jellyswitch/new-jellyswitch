class CreateUserPaymentProfiles < ActiveRecord::Migration[7.0]
  def change
    create_table :user_payment_profiles do |t|
      t.references :user, null: false, foreign_key: true
      t.references :location, null: false, foreign_key: true
      t.string :stripe_customer_id
      t.boolean :card_added, default: false, null: false
      t.boolean :bill_to_organization, default: false, null: false

      t.timestamps

      # Ensure a user can only have one payment profile per location
      t.index [:user_id, :location_id], unique: true
    end
  end
end
