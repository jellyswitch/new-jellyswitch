class CreateDayPassTypeRooms < ActiveRecord::Migration[7.2]
  def change
    create_table :day_pass_type_rooms do |t|
      t.references :day_pass_type, null: false, foreign_key: true, index: false
      t.references :room, null: false, foreign_key: true
      t.integer :position, null: false
      t.timestamps
    end
    add_index :day_pass_type_rooms, [:day_pass_type_id, :room_id], unique: true,
              name: "index_dpt_rooms_on_type_and_room"
    add_index :day_pass_type_rooms, [:day_pass_type_id, :position],
              name: "index_dpt_rooms_on_type_and_position"
  end
end
