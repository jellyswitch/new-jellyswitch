class AddPastMemberGraceDaysToLocations < ActiveRecord::Migration[7.0]
  def change
    add_column :locations, :past_member_grace_days, :integer, default: 180, null: false
  end
end
