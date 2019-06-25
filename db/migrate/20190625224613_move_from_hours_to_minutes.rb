class MoveFromHoursToMinutes < ActiveRecord::Migration[5.2]
  def change
    add_column :reservations, :minutes, :integer, null: false, default: 0
    Reservation.all.each do |res|
      res.update(minutes: res.hours * 60)
    end
  end
end
