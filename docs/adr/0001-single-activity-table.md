# Single `activities` table over virtual timeline

The CRM's per-Person timeline (the "I GET IT" surface) needs to render every event in a Person's history — emails sent/opened/clicked/replied, tours, check-ins, door punches, reservations, day-passes, subscriptions, payments, notes — in chronological order. We chose to materialize all of these as rows in a single `activities` table written at the moment each event happens, rather than querying source tables and merging at read time.

## Considered Options

- **Single `activities` table (chosen).** One row per event with `kind`, `occurred_at`, polymorphic `subject` link back to the source record, and denormalized `payload` JSONB. Writers add rows from `after_create` callbacks, mailer hooks, and webhook receivers.
- **Virtual timeline.** Don't store activities. At read time, query 6+ source tables (CampaignSend, Reservation, Checkin, DayPass, Invoice, LeadNote, DoorPunch) and merge in Ruby.
- **Hybrid.** Start virtual; materialize when read performance hurts.

## Why we chose materialized

1. **Email tracking forces it.** Sendgrid open/click/reply webhooks land async, sometimes days after the original send, and don't map cleanly to any existing source table. We need a write target for those events anyway. Once that target exists, every other event should match the shape — having two timeline architectures is worse than one.
2. **Lead scoring later.** Scoring is "count of recent activities weighted by kind." With the materialized table that's one query; with virtual it's six.
3. **The "I GET IT" moment fails the day a reply doesn't show up.** Adding a new activity kind to a virtual timeline requires updating the merge code in N places. Adding it to the materialized table is one `Activity.log(...)` call.

## Consequences

- **Write amplification.** Every Reservation/Checkin/DayPass/Subscription/Invoice/CampaignSend create now writes a second row. Acceptable: these are low-frequency events, and writes go through `after_create` callbacks so the cost is amortized.
- **Backfill required.** A one-time job populates activity rows from existing source data. Bounded to the last 2 years (per CONTEXT.md).
- **Source records are immutable history sources.** Activity rows carry a polymorphic FK back to the source. If the source is later deleted, the activity row's denormalized payload is the durable record.
- **Discipline cost.** Anyone adding a new event-emitting feature must remember to call `Activity.log(...)`. Mitigated by writing the calls in the same callback as the source-table create.
