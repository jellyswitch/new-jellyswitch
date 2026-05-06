class AddRefundFeePercentToOperators < ActiveRecord::Migration[7.1]
  def change
    # Operators can configure a flat % the space keeps when issuing
    # member refunds — typically to cover Stripe's processing fee on
    # the original charge (Stripe doesn't refund the % fee on a
    # refund). 0 = full refund (default, prior behavior).
    add_column :operators, :refund_fee_percent, :integer, default: 0, null: false
  end
end
