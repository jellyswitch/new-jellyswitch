class CreateConciergeConversations < ActiveRecord::Migration[7.2]
  def change
    create_table :concierge_conversations do |t|
      t.references :operator, null: false, foreign_key: true
      t.references :location, foreign_key: true
      t.references :user, foreign_key: true # set once the visitor is captured
      t.string :session_token, null: false
      t.string :status, null: false, default: "open"
      t.datetime :last_visitor_message_at
      t.datetime :last_staff_message_at
      t.boolean :staff_alerted, null: false, default: false
      t.timestamps
    end
    add_index :concierge_conversations, :session_token, unique: true
    add_index :concierge_conversations, [:operator_id, :status]

    create_table :concierge_messages do |t|
      t.references :concierge_conversation, null: false, foreign_key: true
      t.references :operator, null: false, foreign_key: true
      t.references :author, foreign_key: { to_table: :users } # staff User; null for visitor/bot
      t.string :role, null: false # visitor | staff | bot
      t.text :body, null: false
      t.timestamps
    end
  end
end
