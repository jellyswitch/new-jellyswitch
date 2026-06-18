class AddConciergeEnabledToOperators < ActiveRecord::Migration[7.2]
  def change
    add_column :operators, :concierge_enabled, :boolean, default: false, null: false
  end
end
