class AddLocationIdToDayPassTypesAndPlanCategories < ActiveRecord::Migration[7.0]
  def change
    add_column :day_pass_types, :location_id, :integer
    add_index :day_pass_types, :location_id

    add_column :plan_categories, :location_id, :integer
    add_index :plan_categories, :location_id
  end
end
