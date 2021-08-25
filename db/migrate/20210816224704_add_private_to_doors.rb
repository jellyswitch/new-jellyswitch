class AddPrivateToDoors < ActiveRecord::Migration[6.1]
  def change
    add_column :doors, :private, :boolean
  end
end
