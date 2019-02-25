class CreateProducts < ActiveRecord::Migration[5.2]
  def change
    create_table :products do |t|
      t.string :name, null: false
      t.integer :price, null: false, default: 0
      t.integer :operator_id, null: false
      t.boolean :available, default: true, null: false
      t.boolean :visible, default: true, null: false

      t.timestamps
    end
  end
end
