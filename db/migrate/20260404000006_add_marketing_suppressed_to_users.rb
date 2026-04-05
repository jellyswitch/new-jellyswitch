class AddMarketingSuppressedToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :marketing_suppressed, :boolean, null: false, default: false
    add_column :users, :marketing_suppressed_reason, :string
    add_column :users, :inactive_dismissed_at, :datetime
  end
end
