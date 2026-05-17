class AddHomeGeoToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :home_latitude,  :decimal, precision: 10, scale: 7
    add_column :users, :home_longitude, :decimal, precision: 10, scale: 7
    add_column :users, :home_city,      :string
    add_column :users, :home_state,     :string
    add_index  :users, [:home_state, :home_city]
  end
end
