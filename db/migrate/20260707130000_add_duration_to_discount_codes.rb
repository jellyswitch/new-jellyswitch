class AddDurationToDiscountCodes < ActiveRecord::Migration[7.1]
  # "once" = discount applies to the first payment only (the prior hardcoded
  # behavior); "forever" = discount recurs on every payment for the life of a
  # subscription. Backfills every existing code to "once" so behavior is
  # unchanged until an operator opts a code into recurring.
  def change
    add_column :discount_codes, :duration, :string, null: false, default: "once"
  end
end
