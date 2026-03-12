class CreateFeedbackReplies < ActiveRecord::Migration[7.1]
  def change
    create_table :feedback_replies do |t|
      t.references :member_feedback, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.text :body, null: false
      t.integer :operator_id, null: false
      t.timestamps
    end
    add_index :feedback_replies, :operator_id
  end
end
