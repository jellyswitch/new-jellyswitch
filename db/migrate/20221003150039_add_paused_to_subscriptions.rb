class AddPausedToSubscriptions < ActiveRecord::Migration[7.0]
  def up
    add_column :subscriptions, :paused, :boolean, default: false, null: false
  end

  def down
    remove_column :subscriptions, :paused, :boolean
  end
end
