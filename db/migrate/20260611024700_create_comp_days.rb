class CreateCompDays < ActiveRecord::Migration[7.1]
  def change
    create_table :comp_days do |t|
      t.references :user,         null: false, foreign_key: true
      t.references :operator,     null: false
      t.references :location,     null: false, foreign_key: true
      t.references :granted_by,   null: true,  foreign_key: { to_table: :users }
      t.references :subscription, null: true,  foreign_key: true
      t.date   :occurred_on, null: false
      t.string :reason

      t.timestamps
    end

    add_index :comp_days, [:user_id, :location_id, :occurred_on]
  end
end
