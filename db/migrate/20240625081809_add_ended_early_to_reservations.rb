class AddEndedEarlyToReservations < ActiveRecord::Migration[7.0]
  def change
    add_column :reservations, :ended_early, :boolean, default: false
  end
end
