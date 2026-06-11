# Day Pool limits gate building access, not membership identity

## Context

Plans can cap the number of distinct days a member uses the space per period (`Plan.has_day_limit` / `day_limit`, operator-facing "Monthly Limit"). The original 2017-era implementation evaluated the cap inside `has_days_left?`, which was called from `has_active_subscription?` / `has_active_subscription_at_location?` — so exhausting the cap made the member cease to be a Member everywhere (lifecycle badge, room visibility, dashboard). That blast radius caused a bug, and in Sept 2020 the whole feature was disabled with `return true # ignore day limits for now` (commit `4e164215`). It stayed off for ~6 years.

## Decision

Re-enable the cap, but **decouple it from membership identity**:

- Exhausting the **Day Pool** revokes **building access only**. The member stays a Member — still billed, still rendered active, Hour Pool untouched. `has_active_subscription?` no longer calls `has_days_left?`; the gate lives on the building-access path and the `hit_membership_limit?` banner.
- A day is consumed by a **door punch** (physical entry), not by a reservation. A no-show costs no day. The flow is frictionless; mistakes are corrected by an admin **Comp Day**, not by attendance reconciliation.
- Usage is **date-aware and anchored to the billing period** (Stripe period, or the `start_date` anniversary window for comps) — the same window the Hour Pool uses — and **location-scoped** (door punch resolved via `door.location_id`). A door punch or reservation draws from the pool of the period it falls in, so booking/entering for a future period draws from that period's fresh pool. This abandons the old calendar-month `this_month` counting for the Day Pool.

## Consequences

- Running out of days no longer corrupts member-state reporting — the original bug cannot recur.
- The Day Pool and Hour Pool now share one period concept, so "your monthly allowance" means one window for both.
- Day-limit plans must grant access at exactly one location for the location scope to be meaningful; a roaming multi-location plan would need an explicit operator-wide opt-in (not built).
