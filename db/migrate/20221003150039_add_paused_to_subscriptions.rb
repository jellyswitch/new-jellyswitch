class AddPausedToSubscriptions < ActiveRecord::Migration[7.0]
  def up
    add_column :subscriptions, :paused, :integer, default: 0, null: false
  end

  def down
    remove_column :subscriptions, :paused
  end
end
