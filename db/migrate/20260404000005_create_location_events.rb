class CreateLocationEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :location_events do |t|
      t.references :operator, null: false
      t.references :location
      t.date :date, null: false
      t.string :name, null: false
      t.timestamps
    end
  end
end
