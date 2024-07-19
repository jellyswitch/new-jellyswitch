class RemoveAvAndWhiteboardFromRooms < ActiveRecord::Migration[6.1]
  def up
    remove_column :rooms, :av
    remove_column :rooms, :whiteboard
  end

  def down
    add_column :rooms, :av, :boolean, default: false, null: false
    add_column :rooms, :whiteboard, :boolean, default: false, null: false

    Room.find_each do |room|
      room.update(
        av: room.amenities.exists?(name: Amenity::AV_EQUIPMENT),
        whiteboard: room.amenities.exists?(name: Amenity::WHITEBOARD),
      )
    end
  end
end
