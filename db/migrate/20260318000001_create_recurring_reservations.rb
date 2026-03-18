class CreateRecurringReservations < ActiveRecord::Migration[7.1]
  def change
    create_table :recurring_reservations do |t|
      t.integer :user_id, null: false
      t.integer :room_id, null: false
      t.string :title, null: false
      t.string :recurrence_pattern, null: false
      t.integer :duration_minutes, null: false
      t.time :time_of_day, null: false
      t.integer :day_of_week
      t.integer :day_of_month
      t.date :start_date, null: false
      t.date :end_date, null: false
      t.boolean :cancelled, default: false, null: false
      t.integer :operator_id, null: false
      t.bigint :location_id

      t.timestamps
    end

    add_index :recurring_reservations, :room_id
    add_index :recurring_reservations, :user_id
    add_index :recurring_reservations, :operator_id

    add_column :reservations, :recurring_reservation_id, :bigint
    add_index :reservations, :recurring_reservation_id
  end
end
