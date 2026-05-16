class AddCoolDownDaysToCampaigns < ActiveRecord::Migration[7.0]
  def change
    add_column :campaigns, :cool_down_days, :integer, default: 30, null: false
  end
end
