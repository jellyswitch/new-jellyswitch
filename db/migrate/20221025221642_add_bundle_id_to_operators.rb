class AddBundleIdToOperators < ActiveRecord::Migration[7.0]
  def change
    add_column :operators, :bundle_id, :string
  end
end
