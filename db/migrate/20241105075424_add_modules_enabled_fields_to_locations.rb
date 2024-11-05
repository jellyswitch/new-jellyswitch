class AddModulesEnabledFieldsToLocations < ActiveRecord::Migration[7.0]
  def change
    add_column :locations, :announcements_enabled, :boolean, null: false, default: true
    add_column :locations, :events_enabled, :boolean, null: false, default: true
    add_column :locations, :door_integration_enabled, :boolean, null: false, default: true
    add_column :locations, :rooms_enabled, :boolean, null: false, default: true

    # default false ones
    add_column :locations, :offices_enabled, :boolean, null: false, default: false
    add_column :locations, :bulletin_board_enabled, :boolean, null: false, default: false
    add_column :locations, :credits_enabled, :boolean, null: false, default: false
    add_column :locations, :childcare_enabled, :boolean, null: false, default: true
    add_column :locations, :crm_enabled, :boolean, null: false, default: true
  end
end
