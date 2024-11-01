class AddLocationIdToOrganizations < ActiveRecord::Migration[7.0]
  def change
    add_column :organizations, :location_id, :integer
    add_index :organizations, :location_id
  end
end
