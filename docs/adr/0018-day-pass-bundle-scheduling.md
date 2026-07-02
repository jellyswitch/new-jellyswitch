# 0018 — Day Pass Bundle scheduling (reserve-ahead via dated DayPass)

## Status
Accepted (2026-06-29)

## Context
Bundle redemption was today-only (`ConsumeOnEntry`), but members who wanted an
upcoming day bought a separate single pass for that date on top of their pack
and double-paid (confirmed live; recurring). ADR 0017 established that a
member-initiated redemption is the *same burn* as a door entry.

## Decision
A scheduled day is a normal burn, dated to a future day: mint a bundle-sourced
`DayPass(day: <future date>)`, decrement `passes_remaining`, and log a
`DayPassBundleRedemption(kind: :entry)` — no new model, no new door logic (the
existing once-per-business-day guard and access check handle the day).

- **Deduct now** (confirmed reservation), not at entry.
- **Self-serve cancel before the day starts** restores the pass to the
  originating bundle and logs a new `:schedule_cancel` redemption; once the day
  begins it is spent (`admin_restore` still covers genuine mistakes).
- Draw from the **soonest-expiring** bundle, then oldest.
- **90-day** horizon; reject past dates, already-covered dates, and dates past a
  bundle's expiration.
- **Guests stay today-only** (out of scope).
- A **purchase guardrail** warns a bundle-holder buying a single pass for a day
  their pack could cover.

## Consequences
- Revenue recognition is unchanged (ADR 0009): scheduling spends prepaid value,
  $0 at schedule time; bundle-sourced passes stay out of day-pass revenue.
- Expiration rules unchanged (ADR 0008); a scheduled date may not exceed the
  drawn bundle's expiration.
- Operators gain advance visibility: scheduled days appear on the daily roster.
