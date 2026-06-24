class AddReservationToDayPassBundleRedemptions < ActiveRecord::Migration[7.2]
  # Phase 5 of the reservation billing redesign (ADR 0015): a reservation can
  # redeem one bundle pass ("use 1 pass for today"). The redemption links back to
  # the reservation so a cancel before the coverage day can restore the pass.
  # Additive + reversible. Index built CONCURRENTLY since redemptions can be large.
  disable_ddl_transaction!

  def change
    add_column :day_pass_bundle_redemptions, :reservation_id, :bigint
    add_index :day_pass_bundle_redemptions, :reservation_id, algorithm: :concurrently
  end
end
