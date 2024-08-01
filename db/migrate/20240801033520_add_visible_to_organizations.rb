class AddVisibleToOrganizations < ActiveRecord::Migration[7.0]
  def change
    add_column :organizations, :visible, :boolean, default: true, null: false
  end
end
