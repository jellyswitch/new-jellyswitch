# Lifecycle stage is derived at query time, not stored

A Person's lifecycle stage (Member / Day-passer / Tour-taker / Past member / Quiet) is derived at query time from subscription state, last-activity timestamps, and Lead annotations — not stored as an enum column on `User`. Operator-facing UI presents the stage as a label and a filter; underneath it's a query.

## Considered Options

- **Derived at query time (chosen).** Stages computed from `User.subscription`, `User.activities.maximum(:occurred_at)`, `Lead.where(user: ...)`, and `Location.past_member_grace_days`. Materialized into a SQL view or a class method on `User`.
- **Stored enum.** `User.lifecycle_stage` column maintained by callbacks and a nightly job that re-derives.
- **Hybrid.** Stored, but recomputed on read if stale.

## Why derived

1. **The data already says it.** Subscription status and activity recency are the source of truth; an enum column would just be a denormalization of those signals. Denormalizations drift.
2. **Stage transitions are inherently lossy when stored.** The "Quiet" stage depends on rolling 30-day activity. Stored as an enum, it requires a nightly cron that flips users in and out of "Quiet" at midnight — guaranteed to be wrong between midnight and the next cron run.
3. **Past-member grace period is per-location.** A stored enum needs to be recomputed every time the operator changes the grace setting. A derived stage just reads the current setting at query time.
4. **No caller cares about historical stage.** Operators want to know "what is this person right now?" — not "what was their lifecycle stage on March 14?" If that question ever arises, the activity table answers it directly.

## Consequences

- **No `lifecycle_stage` enum column on `User`.** Don't add one when implementing. The temptation will be there.
- **Filter queries are slower than enum-indexed lookups.** Mitigated by indexing the underlying signals (`activities(user_id, occurred_at)`, `subscriptions(user_id, status)`) and by limiting the People list page size.
- **Test fixtures need real activity data.** A `:tour_taker` factory must create a User + a tour Activity, not just a User with `lifecycle_stage: :tour_taker`. This is good — tests stay honest about the data model.
- **Adding a new stage is a query change, not a migration.** "Trial member" or "VIP" can be added to the derivation logic without touching schema.
