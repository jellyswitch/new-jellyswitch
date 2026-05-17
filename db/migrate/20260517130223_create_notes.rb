class CreateNotes < ActiveRecord::Migration[7.1]
  def change
    create_table :notes do |t|
      t.references :notable, polymorphic: true, null: false, index: true
      t.references :operator, null: false, foreign_key: true, index: true
      t.references :author, null: false, foreign_key: { to_table: :users }, index: true
      t.text :body, null: false

      t.timestamps
    end

    add_index :notes, [:operator_id, :created_at]
  end
end
