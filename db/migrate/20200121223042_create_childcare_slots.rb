class CreateChildcareSlots < ActiveRecord::Migration[6.0]
  def change
    create_table :childcare_slots do |t|
      t.string :name
      t.integer :week_day
      t.boolean :deleted
      t.integer :location_id

      t.timestamps
    end
  end
end
