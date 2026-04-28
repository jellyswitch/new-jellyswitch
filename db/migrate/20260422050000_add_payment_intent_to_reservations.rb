class AddPaymentIntentToReservations < ActiveRecord::Migration[7.1]
  def change
    add_column :reservations, :stripe_payment_intent_id, :string
    add_column :reservations, :authorized_amount_in_cents, :integer
    add_column :reservations, :captured_amount_in_cents, :integer
    add_column :reservations, :captured_at, :datetime
    add_index :reservations, :stripe_payment_intent_id, unique: true
  end
end
