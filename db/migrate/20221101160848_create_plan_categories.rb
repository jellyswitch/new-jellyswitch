class CreatePlanCategories < ActiveRecord::Migration[7.0]
  def change
    create_table :plan_categories do |t|
      t.string :name
      t.integer :operator_id

      t.timestamps
    end
  end
end
