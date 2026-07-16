class AddMissingPerformanceIndexes < ActiveRecord::Migration[7.2]
  # Adds the hot-path indexes the 2026-07-14 performance audit flagged. Each
  # column below is filtered on constantly but was doing a sequential scan of a
  # large multi-tenant table — the main driver of slow availability checks,
  # webhook lookups, and the feed/CRM pages under the tight prod connection pool.
  #
  # All built CONCURRENTLY (no write lock) since these tables are large in prod;
  # `disable_ddl_transaction!` is required for that. `if_not_exists: true` makes
  # the migration safe to re-run — the release phase runs each `add_index`
  # outside a transaction, so a retry after a partial/timed-out build skips the
  # indexes already created instead of erroring.
  disable_ddl_transaction!

  def change
    # Reservation overlap / availability (room.reservations.overlapping filters
    # room_id + a datetime_in range) and the mobile unlock reservation-window
    # check (user.reservations.where(datetime_in: range)).
    add_index :reservations, [:room_id, :datetime_in],
              algorithm: :concurrently, if_not_exists: true
    add_index :reservations, [:user_id, :datetime_in],
              algorithm: :concurrently, if_not_exists: true

    # Stripe webhook lookups — Invoice.exists?/find_by(stripe_invoice_id:) and
    # Subscription.find_by(stripe_subscription_id:) run on every relevant event.
    # Non-unique on purpose: re-imports can transiently duplicate
    # stripe_invoice_id (see the TLH migration notes), so we don't add a unique
    # constraint here.
    add_index :invoices, :stripe_invoice_id,
              algorithm: :concurrently, if_not_exists: true
    add_index :subscriptions, :stripe_subscription_id,
              algorithm: :concurrently, if_not_exists: true

    # Day-pass-by-member lookups: the mobile unlock path
    # (user.day_passes.where(day: today)) and lifecycle_stage's recent_day_pass?.
    add_index :day_passes, [:user_id, :day],
              algorithm: :concurrently, if_not_exists: true

    # Operator feed page: FeedItem.for_operator(current_tenant)
    # .order("updated_at DESC") — was seq-scanning + sorting the biggest table
    # (only location_id and the gin blob index existed).
    add_index :feed_items, [:operator_id, :updated_at],
              algorithm: :concurrently, if_not_exists: true
  end
end
