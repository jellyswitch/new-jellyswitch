class AddNotificationSettingsToOperator < ActiveRecord::Migration[6.0]
  def change
    add_column :operators, :reservation_notifications, :boolean, null: false, default: false
  end
end
