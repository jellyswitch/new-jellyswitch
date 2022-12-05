class AddPlanCategoryIdToPlans < ActiveRecord::Migration[7.0]
  def change
    add_column :plans, :plan_category_id, :integer
  end
end
