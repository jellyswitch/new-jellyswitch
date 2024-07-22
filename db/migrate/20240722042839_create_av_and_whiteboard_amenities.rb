class CreateAvAndWhiteboardAmenities < ActiveRecord::Migration[6.1]
  def up
    Room.find_each do |room|
      if room.av?
        room.amenities.create!(
          name: Amenity::AV_EQUIPMENT,
          price: 0,
          membership_price: 0,
        )
      end

      if room.whiteboard?
        room.amenities.create!(
          name: Amenity::WHITEBOARD,
          price: 0,
          membership_price: 0,
        )
      end
    end
  end

  def down
    Amenity.where(name: [Amenity::AV_EQUIPMENT, Amenity::WHITEBOARD]).destroy_all
  end
end
