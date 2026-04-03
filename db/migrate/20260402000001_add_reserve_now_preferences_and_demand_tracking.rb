class AddReserveNowPreferencesAndDemandTracking < ActiveRecord::Migration[7.1]
  def change
    # User meeting room preferences
    add_column :users, :preferred_room_id, :bigint
    add_column :users, :preferred_meeting_duration, :integer, default: 60
    add_index :users, :preferred_room_id

    # Demand miss tracking
    create_table :room_demand_misses do |t|
      t.references :user, null: false, foreign_key: true
      t.references :operator, null: false, foreign_key: true
      t.references :location, null: false, foreign_key: true
      t.datetime :missed_at, null: false
      t.integer :day_of_week
      t.integer :hour_of_day
      t.timestamps
    end

    add_index :room_demand_misses, [:location_id, :missed_at]
    add_index :room_demand_misses, [:location_id, :day_of_week, :hour_of_day], name: "idx_demand_misses_heatmap"
  end
end
