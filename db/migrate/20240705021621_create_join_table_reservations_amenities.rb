class CreateJoinTableReservationsAmenities < ActiveRecord::Migration[7.0]
  def change
    create_join_table :reservations, :amenities do |t|
      t.index [:reservation_id, :amenity_id]
      t.index [:amenity_id, :reservation_id]
    end

    add_foreign_key :amenities_reservations, :reservations
    add_foreign_key :amenities_reservations, :amenities
  end
end
