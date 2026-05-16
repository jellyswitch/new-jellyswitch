class AddDefaultForRoomBookingToDayPassTypes < ActiveRecord::Migration[7.1]
  def change
    add_column :day_pass_types, :default_for_room_booking, :boolean, default: false, null: false
    add_index :day_pass_types, [:operator_id, :location_id, :default_for_room_booking], name: "index_dpt_on_op_loc_default"
  end
end
