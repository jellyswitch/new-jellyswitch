class AddPrivateDoors < ActiveRecord::Migration[6.0]
  def change
    add_column :doors, :private, :boolean
  end
end
