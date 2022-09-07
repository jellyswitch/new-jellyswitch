class AddCancellingAtEndOfBillingPeriodToSubscriptions < ActiveRecord::Migration[6.1]
  def up
    add_column :subscriptions, :cancelling_at_end_of_billing_period, :boolean, default: false, null: false
  end

  def down
    remove_column :subscriptions, :cancelling_at_end_of_billing_period
  end
end
