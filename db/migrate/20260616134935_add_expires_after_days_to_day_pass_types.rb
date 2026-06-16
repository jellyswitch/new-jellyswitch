class AddExpiresAfterDaysToDayPassTypes < ActiveRecord::Migration[7.2]
  def change
    add_column :day_pass_types, :expires_after_days, :integer
  end
end
