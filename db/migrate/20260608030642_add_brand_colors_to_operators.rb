class AddBrandColorsToOperators < ActiveRecord::Migration[7.2]
  def change
    add_column :operators, :primary_color, :string
    add_column :operators, :accent_color, :string
  end
end
