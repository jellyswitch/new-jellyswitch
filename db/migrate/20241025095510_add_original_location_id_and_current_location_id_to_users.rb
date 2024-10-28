class AddOriginalLocationIdAndCurrentLocationIdToUsers < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :original_location_id, :integer
    add_column :users, :current_location_id, :integer
  end
end
