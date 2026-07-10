class BackfillLastPurchaseInterestTags < ActiveRecord::Migration[7.1]
  # Seed last_purchase interest tags from existing purchases so the audience
  # lists fill up retroactively (ADR 0022). Idempotent (InterestTag.record upserts
  # one row per user+product) and staff-safe (record() no-ops on staff-set tags).
  # These operators are small coworking spaces, so a release-phase backfill is
  # cheap; find_each batches regardless.
  def up
    count = 0

    ActsAsTenant.without_tenant do
      # day_pass: replay day_pass Activities. Imported passes (redemptions, burns,
      # historical imports) never logged one, so this excludes them for free.
      Activity.where(kind: "day_pass").find_each do |a|
        count += 1 if a.user && InterestTag.record(user: a.user, product: "day_pass", source: "last_purchase", at: a.occurred_at)
      end

      # day_pass (bundles): no Activity kind exists; every bundle row is a purchase.
      DayPassBundle.find_each do |b|
        count += 1 if b.user && InterestTag.record(user: b.user, product: "day_pass", source: "last_purchase", at: b.created_at)
      end

      # membership: individual, non-lease subscriptions (office-lease subs excluded).
      Subscription.where(subscribable_type: "User").includes(:plan).find_each do |s|
        next if s.plan&.lease? || s.subscribable.nil?
        count += 1 if InterestTag.record(user: s.subscribable, product: "membership", source: "last_purchase", at: s.created_at)
      end

      # meeting_room: paid-room reservations only. UNSCOPED so cancelled bookings
      # are included — the live hook tags at booking time (before any cancel), so a
      # later cancellation must not exclude a buyer here. (Reservation has
      # default_scope { where(cancelled: false) }.)
      Reservation.unscoped.includes(:room).find_each do |r|
        next unless r.user && r.room&.paid_room?
        count += 1 if InterestTag.record(user: r.user, product: "meeting_room", source: "last_purchase", at: r.created_at)
      end
    end

    say "Backfilled #{count} last_purchase interest tags"
  end

  def down
    # Only removes purchase-seeded tags; staff/concierge/other tags are untouched.
    InterestTag.where(source: "last_purchase").delete_all
  end
end
