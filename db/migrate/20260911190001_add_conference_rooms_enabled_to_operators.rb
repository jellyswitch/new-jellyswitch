class AddConferenceRoomsEnabledToOperators < ActiveRecord::Migration[7.2]
  # Conference Rooms website widget (2026-09-11): the operator-level on/off
  # switch, same shape as showcase_enabled / office_inventory_enabled.
  def change
    add_column :operators, :conference_rooms_enabled, :boolean, default: false, null: false
  end
end
