# Day Pass Bundle Scheduling — Design Spec

- **Date:** 2026-06-29
- **Status:** Approved (brainstorming) — pending implementation plan
- **Scope:** new-jellyswitch (Rails) + jellyswitch-mobile (Expo) + web admin/member
- **Related:** ADR 0008 (bundle expiration), ADR 0009 (revenue at sale), ADR 0017 (member-initiated redemption is the same burn), `CONTEXT.md` → "Day Pass Bundle"

## Problem & motivation

A member buys a Day Pass **Bundle** (N-Pack), then — wanting to come in on an **upcoming** day — buys a **separate single day pass** for that future date instead of using a bundle pass, and double-pays. Confirmed live: Cowork Tahoe member Katelyn (#76132) bought a $70 two-pack, then a $40 single for the **next day** ~2 min later; she confirmed in-app it was a mistake, and the operator reports she is not the only one.

**Root cause is a real product gap, not just confusing UI.** Redeeming a bundle pass (`Billing::DayPassBundles::ConsumeOnEntry`) is **today-only** — it mints a `DayPass` for the current business day and takes no date. Meanwhile the single-day-pass **purchase** flow lets a member pick a future date. So "use a bundle day next Tuesday" has no path, and members buy a single for that date on top of their pack. `CONTEXT.md` currently documents this limitation explicitly: *"There is no scheduling — passes are not assigned to future dates."* This spec reverses that decision.

## Goals

1. Let a member **schedule** a bundle pass for one or more **future days** (self-serve), so they never need to buy a single for a day their pack already covers.
2. Let an **operator/admin** schedule bundle day(s) on a member's behalf.
3. **Prevent the accidental double-buy**: warn a bundle-holder who tries to buy a single pass for a day their pack could cover.
4. Reuse existing burn-on-entry, redemption ledger, door access, and revenue rules with minimal new surface area.

## Non-goals (v1)

- **Guest passes stay today-only** — scheduling a guest day is out of scope.
- No waitlist/capacity management for days.
- No change to single-day-pass purchase pricing or to bundle pricing.
- No operator-configurable scheduling horizon yet (fixed default, see Constraints).

## Decisions (settled in brainstorming)

| # | Decision |
|---|----------|
| Scope | Member can schedule **one or many** future days; **admins** can schedule on a member's behalf. |
| Burn timing | **Deduct now** — scheduling immediately decrements `passes_remaining` and mints a dated `DayPass` (a confirmed reservation). |
| Cancellation | **Self-serve before that day starts**; the pass returns to the balance. Once the day begins, it's spent. |
| Guardrail | **Yes** — warn on the single-pass purchase flow when the buyer holds bundle passes covering that date. |
| Multi-pack draw | Draw from the pack that **expires soonest**, then oldest. |
| Guests | **Today-only** (out of scope for scheduling in v1). |
| Horizon | Default **90 days** ahead (not yet operator-configurable). |

## Approach (chosen: reuse the dated `DayPass` + Redemption ledger)

A scheduled day is exactly what a burn produces today, dated to a future day. A bundle-sourced `DayPass(day: <future date>)` is minted from the bundle, `passes_remaining` is decremented, and a `DayPassBundleRedemption(kind: :entry)` is logged — identical to today's burn, with the date as a parameter. On the scheduled day, the **existing** door access check sees a `DayPass` covering that day and opens it; the existing once-per-business-day burn guard prevents any double-burn. No new "covered day" concept, no new door-time logic.

*Rejected alternative:* a separate `ScheduledPass` model that converts to a `DayPass` at entry — duplicates the "covered day" concept, needs brand-new door-time conversion logic and a second source of truth. Heavier, fights the existing model.

## Domain model & data changes

**No new tables.**

- **`DayPass.day` may now be in the future.** Audit the "today" assumptions that touch day passes (door access check, "who's coming today" roster, daily totals) to confirm they handle a future-dated pass cleanly (a future-dated pass is simply not yet "today" until its date arrives; on its date it matches `for_day(today)`).
- **New redemption kind `:schedule_cancel`** on `DayPassBundleRedemption` (joins `entry | guest | admin_restore`) — the reversal logged when a member/admin cancels a still-future scheduled day. `admin_restore` remains for genuine post-hoc mistakes.

**Interactors (Rails):**

- `Billing::DayPassBundles::ScheduleDay` — generalizes `ConsumeOnEntry`. Inputs: `user`, `location`, `date`, `performed_by`. Under the **bundle row lock** (reuse `burn_locked!`): pick the eligible bundle (soonest-expiring, then oldest), mint `DayPass(day: date, day_pass_type: bundle.day_pass_type, bundle-sourced, complimentary: false, no stripe_charge_id)`, decrement `passes_remaining`, log `Redemption(kind: :entry, day_pass:, performed_by:)`. For `date == today` this is the existing immediate burn (the current `redeem_today` path is preserved unchanged — "today" simply routes through the same logic).
- `Billing::DayPassBundles::ScheduleDays` — batches N dates in **one transaction**; partial failure rolls back the whole batch (all-or-nothing).
- `Billing::DayPassBundles::CancelScheduledDay` — inputs: the scheduled `DayPass`, `performed_by`. Allowed only while `date` is still in the future (before that location-day's `business_day_window` start). **Destroys** the future `DayPass` (it never granted access, so there is nothing to preserve on the pass itself; the `schedule_cancel` redemption is the audit record), increments `passes_remaining` **on the originating bundle** (resolved via the redemption's `day_pass_id` link), and logs `Redemption(kind: :schedule_cancel, performed_by:)`.

## Constraints & invariants

- Reject when `passes_remaining < 1` (and for multi-day, when fewer passes than requested dates).
- Reject a date the member is **already covered** for: an existing `DayPass.for_day(date)`, an active lease, or a subscription covering that location/date — never waste a pass.
- **One bundle pass per member per day** (a day is covered or not).
- Reject **past dates** and dates **beyond the 90-day horizon**.
- Reject a date **beyond the chosen pack's expiration** (if expiration is enabled — ADR 0008).
- A scheduled pass is tied to the **bundle's location** (location-scoped, like all bundle access).
- `passes_remaining` never negative; the redemption ledger remains the full audit trail.
- Concurrency: minting/decrement/log run under the existing bundle row lock so concurrent schedule/cancel/door-burn cannot double-spend.

## Behavior at the door, money, and reporting

- **Door:** on the scheduled day the member already holds a bundle-sourced `DayPass` for that day → existing access check grants entry; the once-per-business-day burn guard means no second pass is burned. No new door logic.
- **Revenue:** scheduling spends already-recognized prepaid value → **$0** at schedule time (ADR 0009 unchanged); a bundle-sourced pass carries no charge and stays excluded from day-pass revenue via the existing `not_bundle_sourced` scope.
- **Roster (bonus):** because a scheduled day is a real dated `DayPass`, the member appears on the "who's coming today" roster **on their scheduled day** — operators see planned visits in advance.

## API surface (Rails)

- `POST /day_passes/redeem_today` — **unchanged** (today's burn).
- `POST /day_pass_bundles/schedule` — body: `dates: [ISO date, …]` (member, own active bundle). Returns updated `passes_remaining` + scheduled days.
- `GET /day_pass_bundles/scheduled_days` — member's upcoming scheduled days.
- `POST /day_passes/:id/cancel_scheduled` — cancel a still-future scheduled day; returns updated balance.
- Admin namespace variants for scheduling/listing/cancelling on a target member's behalf.

## Member UX (mobile + web)

- Day Pass screen keeps **"Use a pass for today"** exactly as-is (`DayPassScreen.js` / `WelcomeScreen.js` → `redeem_today`).
- New secondary action **"Schedule a day…"** → calendar to select one or more upcoming dates (disabled: past, already-covered, beyond horizon/expiry; selection capped at passes remaining), confirming "This uses N of your M passes."
- New **"Scheduled days"** list below it — each upcoming date with a **Cancel (✕)** available until that day starts; confirmation + haptic + balance refresh.
- **Purchase guardrail:** in the single-day-pass buy flow, if the member holds bundle passes covering the chosen date, show "You already have N passes — use one instead?" with a one-tap CTA that routes to schedule.

## Admin UX (mobile + web)

- From a member's profile / day-pass admin: **schedule day(s) on their behalf** (same picker), **view** their upcoming scheduled days, and **cancel** one (restores the pass). Existing **admin_restore** stays for genuine post-hoc mistakes.

## Documentation changes (required)

- **`CONTEXT.md` → "Day Pass Bundle":** rewrite the *"There is no scheduling — passes are not assigned to future dates"* sentence to describe scheduling (deduct-now, dated pass, self-serve cancel-before-day, soonest-expiring draw, guests still today-only); add `:schedule_cancel` to the redemption-kind list; add the roster note.
- **New ADR `docs/adr/0018-day-pass-bundle-scheduling.md`:** record the decision — reserve-ahead via dated `DayPass`, deduct-now, self-serve cancel-before-day, soonest-expiring draw, 90-day horizon, guests out of scope, guardrail. Reference ADR 0017 (same-burn) as the precedent and note ADRs 0008/0009 unaffected.

## Testing strategy

- **Backend Minitest** — `ScheduleDay`/`ScheduleDays`: mints a dated bundle-sourced pass, decrements `passes_remaining`, logs an `entry` redemption; blocks over-schedule, already-covered, past, beyond-horizon, beyond-expiry; draws from the soonest-expiring pack; location scoping; multi-day all-or-nothing rollback. `CancelScheduledDay`: restores + voids and logs `schedule_cancel`; blocked once the day has started. A **door/access test** proving a scheduled pass opens the door on its date and does not double-burn. Request tests for the new endpoints (member + admin auth).
- **Mobile jest** — date-picker constraints (no past/too-far, can't exceed passes remaining) and guardrail trigger logic, in the existing `tests/utils` style.

## Open questions / future work

- Operator-configurable horizon (instead of fixed 90 days).
- Guest-day scheduling (deferred from v1).
- Reschedule as a first-class action (v1 = cancel + re-pick).
