class CreateProductEmailSends < ActiveRecord::Migration[7.1]
  def change
    create_table :product_email_sends do |t|
      t.references :operator, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :sendable_type, null: false
      t.bigint :sendable_id, null: false
      t.string :email_type, null: false
      t.string :status, default: "sent"
      t.text :error_message
      t.datetime :sent_at

      t.timestamps
    end

    add_index :product_email_sends, [:sendable_type, :sendable_id, :email_type], unique: true, name: 'idx_product_email_sends_unique'
  end
end
