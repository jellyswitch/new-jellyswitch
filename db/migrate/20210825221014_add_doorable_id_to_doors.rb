class AddDoorableIdToDoors < ActiveRecord::Migration[6.1]
  def change
    add_column :doors, :doorable_id, :integer
  end
end
