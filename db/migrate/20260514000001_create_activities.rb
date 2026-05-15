class CreateActivities < ActiveRecord::Migration[7.1]
  def change
    create_table :activities do |t|
      t.references :user,     null: false, foreign_key: true, index: false
      t.references :operator, null: false, foreign_key: true, index: false
      t.string :kind, null: false
      t.references :subject, polymorphic: true, null: true, index: false
      t.jsonb :payload, null: false, default: {}
      t.datetime :occurred_at, null: false
      t.timestamps
    end

    add_index :activities, [:user_id, :occurred_at]
    add_index :activities, [:operator_id, :kind, :occurred_at]
    add_index :activities, [:subject_type, :subject_id]
  end
end
