class AddLastActivitiesBackfilledAtToOperators < ActiveRecord::Migration[7.1]
  def change
    add_column :operators, :last_activities_backfilled_at, :datetime
  end
end
