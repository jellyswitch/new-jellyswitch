class DropConciergeConversations < ActiveRecord::Migration[7.2]
  # The Concierge no longer runs a separate live-chat inbox — visitor questions
  # route into the existing MemberFeedback channel — so these tables (shipped in
  # 20260618000003, never used in prod) are dropped. Reversible: down recreates
  # them exactly as the original create migration.
  def up
    drop_table :concierge_messages
    drop_table :concierge_conversations
  end

  def down
    create_table :concierge_conversations do |t|
      t.references :operator, null: false, foreign_key: true
      t.references :location, foreign_key: true
      t.references :user, foreign_key: true
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
      t.references :author, foreign_key: { to_table: :users }
      t.string :role, null: false
      t.text :body, null: false
      t.timestamps
    end
  end
end
