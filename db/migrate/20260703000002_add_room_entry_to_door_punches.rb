class AddRoomEntryToDoorPunches < ActiveRecord::Migration[7.2]
  def change
    # Room Entry ≠ door punch (ADR 0021): Room Lock opens are audited in the
    # same table but flagged out of every "member entered the building"
    # semantic (Day Pool, bundle burn-on-entry, entry analytics).
    add_column :door_punches, :room_entry, :boolean, default: false, null: false
  end
end
