class AddQuantityToDayPassTypes < ActiveRecord::Migration[7.1]
  def change
    add_column :day_pass_types, :quantity, :integer, null: false, default: 1
  end
end
