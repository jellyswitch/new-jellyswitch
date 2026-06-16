class AddDayPassPeriodStartToLocations < ActiveRecord::Migration[7.2]
  def change
    add_column :locations, :day_pass_period_start, :string, null: false, default: "04:00"
  end
end
