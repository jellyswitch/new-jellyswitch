class CreateBeacons < ActiveRecord::Migration[7.1]
  def change
    create_table :beacons do |t|
      t.string  :name,        null: false
      t.string  :uuid,        null: false
      t.integer :major,       null: false
      t.integer :minor,       null: false
      t.references :location, null: false, foreign_key: true
      t.references :door,     null: true,  foreign_key: true
      t.integer :operator_id, null: false, default: 1
      t.datetime :last_seen_at
      t.integer  :battery_pct
      t.datetime :installed_at
      t.text     :notes
      t.boolean  :available,  null: false, default: true
      t.timestamps
    end

    add_index :beacons, [:operator_id, :uuid, :major, :minor],
              unique: true,
              name:   "index_beacons_on_operator_uuid_major_minor"
    add_index :beacons, :operator_id
  end
end
