class AddPaymentIntentToInvoices < ActiveRecord::Migration[7.1]
  def change
    add_column :invoices, :stripe_payment_intent_id, :string
    add_column :invoices, :description, :string
    add_column :invoices, :refunded_at, :datetime
    add_column :invoices, :refund_amount_in_cents, :integer
    add_index :invoices, :stripe_payment_intent_id
  end
end
