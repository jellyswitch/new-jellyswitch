class AddBillableToSubscriptions < ActiveRecord::Migration[5.2]
  def change
    add_reference :subscriptions, :billable, polymorphic: true

    Subscription.all.each do |subscription|
      subscription.update(billable: BillableFactory.new(subscription).billable)
    end
  end
end
