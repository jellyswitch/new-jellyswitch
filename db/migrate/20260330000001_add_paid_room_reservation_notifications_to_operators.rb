class AddPaidRoomReservationNotificationsToOperators < ActiveRecord::Migration[7.1]
  def change
    add_column :operators, :paid_room_reservation_notifications, :boolean, null: false, default: true
  end
end
