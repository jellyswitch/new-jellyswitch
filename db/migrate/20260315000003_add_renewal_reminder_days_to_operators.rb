class AddRenewalReminderDaysToOperators < ActiveRecord::Migration[7.1]
  def change
    add_column :operators, :renewal_reminder_days, :integer, default: 7
  end
end
