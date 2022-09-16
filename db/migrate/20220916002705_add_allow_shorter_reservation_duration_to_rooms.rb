class AddAllowShorterReservationDurationToRooms < ActiveRecord::Migration[6.1]
  def up
    add_column :rooms, :allow_shorter_reservation_duration, :boolean, default: true, null: false
  end

  def down
    remove_column :rooms, :allow_shorter_reservation_duration
  end
end
