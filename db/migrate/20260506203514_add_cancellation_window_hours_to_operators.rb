class AddCancellationWindowHoursToOperators < ActiveRecord::Migration[7.1]
  def change
    # Hours-before-start a member must cancel by to be eligible for a
    # refund. Outside the window: cancellation still allowed but the
    # held amount is captured (no refund). Inside the window (= more
    # advance notice): the hold is voided pre-capture or refunded
    # post-capture, with refund_fee_percent retained.
    #
    # 0 = no window (always full refund). Default 24 matches the most
    # common coworking policy.
    add_column :operators, :cancellation_window_hours, :integer, default: 24, null: false
  end
end
