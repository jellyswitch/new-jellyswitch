# Included-Room Booking Commits Day-Pass Coverage — Design Spec

- **Date:** 2026-06-30
- **Status:** Approved (brainstorming) — pending implementation plan
- **Base branch:** `staging/combine-bundle-scheduling` (this EXTENDS the not-yet-merged reservation-billing redesign — Phases 1–7 / ADRs 0010–0015 — and the bundle-scheduling work / ADR 0018; it must branch from the staging line, not `main`).
- **Related ADRs:** 0010 (capture-at-booking), 0012 (universal room pricing / location overage rate), 0013 (reservation access window), 0015 (reserve-time bundle redemption), 0018 (bundle scheduling). **New: ADR 0019.**

## Problem

Booking an **included room** (`hourly_rate_in_cents == 0` AND `include_with_day_pass`) is a commitment to be in the space that day — but on its own it grants only a ±60-min *access window* (ADR 0013), so real coverage for the day depends on holding a day pass. Today's handling is broken:

- Burning a bundle pass at booking is **opt-in only** (`use_bundle_pass: true`, ADR 0015). If the client omits it, `reservations_controller.rb` **silently auto-buys a fresh single day pass** for that date — even when the member holds a bundle — wasting their money.
- There is **no "this will use a day pass" notice** and no real **"buy one?"** prompt.
- **Meeting-room overage** (minutes beyond the day-pass included allowance) must apply regardless of how the day is covered, and must be surfaced so the member isn't surprised.

## Decisions (settled in brainstorming)

| Topic | Decision |
|---|---|
| Bundle-holder | **Confirm before booking** — explicit "use a pass" tap; no silent burn. |
| No coverage committed | **Block the booking** — must reuse a spare pass, use a bundle pass, or buy one; otherwise no reservation. |
| Purchased pass on cancel | **Not refunded, but kept and REUSABLE** for another day. |
| Bundle pass on cancel | **Restored** (day wholly future, pass unused) — with a sibling-booking guard. |
| Overage | Applies against the **covering pass's** included minutes (bundle / purchased / existing), surfaced as a **separate line**. |
| Scope | **Included rooms only.** Paid rooms (`hourly_rate > 0`) untouched. |
| No "buy a single instead" for bundle-holders | A bundle-holder confirm is use-a-pass-or-cancel (offering a single would reinvite double-pay). |

## `CoverageState` — one shared source of truth

`Billing::Reservations::CoverageState.for(user:, room:, date:, location:)` — **read-only, side-effect-free** — returns exactly one outcome, centralizing logic currently split between `reservations_controller.rb:61-67` and `RedeemBundlePass`:

1. **`:not_applicable`** — paid room (`hourly_rate_in_cents > 0`) or not `include_with_day_pass`. Feature doesn't touch it.
2. **`:already_covered`** — active subscription, lease at the location, an existing `DayPass.for_location(location).for_day(date)`, or staff/admin.
3. **`:reusable_pass`** — holds a **purchased** (non-bundle-sourced) day pass that was bought for an included-room booking which is **now cancelled**, still unused, `day >= today`. This is the "leftover from a cancelled booking" case — it can be re-dated to the requested date. Carries the `DayPass`. Deliberately narrow: a pass the member bought for a day they still intend to attend is NOT linked to a cancelled reservation and won't be grabbed.
4. **`:bundle_available`** — active bundle at the room's location. Carries `passes_remaining` and the soonest-expiring bundle (ADR 0018 draw order).
5. **`:needs_purchase`** — none of the above. Carries the location's day-pass type + `amount_in_cents` (the SKU the old silent auto-buy used).

**Precedence:** `not_applicable` > `already_covered` > `reusable_pass` > `bundle_available` > `needs_purchase` (prefer a pass they already paid for before burning a bundle pass or buying a new one). Date-aware: evaluates coverage for the reservation's date (today or future).

### Data model

One migration: add a nullable **`day_passes.reservation_id`** (FK, `on_delete: nullify`). `BuyCoverageDayPass` stamps it with the reservation it was bought for; re-dating a reused pass re-points it at the new reservation. A `:reusable_pass` is precisely a purchased `DayPass` whose `reservation` is **cancelled** (or, defensively, whose linked reservation no longer exists), unused, `day >= today`. This makes "leftover from a cancelled booking" an exact query rather than a fragile heuristic, and it never touches passes a member holds for a day they plan to attend. (Bundle-sourced coverage keeps using the `day_pass_bundle_redemptions.reservation_id` link that already exists — the two coverage sources stay in their own lanes; a bundle-scheduled pass from ADR 0018 is never re-dated by this flow.)

## Overage — a second, independent result

Alongside the coverage outcome, compute this booking's meeting-room overage via the existing `ChargeCalculator#day_pass_overage_cents` semantics, against the **covering** pass's `day_pass_type.included_meeting_room_minutes` (the existing pass, the bundle's `day_pass_type`, or the to-be-purchased type):
- Net of other `include_with_day_pass` bookings already on that date (cumulative daily draw-down).
- Rounded up to 15-min, billed at the **location** overage rate (ADR 0012).
- Only when the covering `day_pass_type.has_meeting_room_limit?` — an unlimited type incurs no overage.

The preview computes this **prospectively** (the covering pass will exist post-commit) so the confirm can display it. A single booking may carry **both** "use 1 pass" and "+ $X overage." "Daypass bundle limits" = the per-day included minutes of the **bundle's** `day_pass_type`.

## Commit — one atomic, enforced step

**New organizer step `Billing::Reservations::CommitCoverage`** in `CreateRoomReservation`, after `SaveRoomReservation`/`ChargeCredits` and **before** `ChargeAtBooking` (so the covering pass exists when overage is priced). Acts on the client's decision flag:

- **`:not_applicable` / `:already_covered`** → no-op.
- **`:reusable_pass` + `use_existing_pass: true`** → **re-date** the spare `DayPass` to the reservation's date (keeps its `invoice` + `day_pass_type`, so the paid purchase and its included-minutes/overage carry over) and link `reservation_id`.
- **`:bundle_available` + `use_bundle_pass: true`** → existing `RedeemBundlePass` (mints the dated pass, `kind:"reservation"`, `reservation_id` linked).
- **`:needs_purchase` + `buy_day_pass: true`** → new sub-step `BuyCoverageDayPass` wrapping `Billing::DayPasses::CreateDayPass`, **stamping `day_passes.reservation_id`**; its `rollback` voids/refunds the purchase if a later organizer step fails (atomic with the reservation — better than today's controller-side buy, which can strand a pass).
- **Coverage required but no decision** (included room, uncovered date, no flag) → `context.fail!` → **HTTP 422**. This is the server-side "block if uncovered" enforcement. **The silent controller auto-buy is deleted.**

Resulting order: `SaveRoomReservation → ChargeCredits → CommitCoverage (reuse | burn | buy) → ChargeAtBooking (prices room + overage against the now-existing pass) → …`. Paid rooms skip `CommitCoverage`.

## API & preview

- **Preview:** extend the **Phase 7 eligibility endpoint** (already exposes bundle eligibility + access window) to include the `CoverageState` outcome + prospective overage for `room + date` — no extra round-trip.
- **Create reservation** accepts one decision flag: `use_existing_pass` | `use_bundle_pass` | `buy_day_pass`. Server enforces via `CoverageState` + `CommitCoverage` (422 if an included, uncovered date arrives with no valid decision). The controller shrinks to: compute `CoverageState`, forward the flag; the silent auto-buy is removed.

## Confirm UX (mobile + web)

Preview once **room + date/time** are chosen; show the matching confirm before "Book":

- **`already_covered`** → no coverage prompt; overage (if any) shows as a line in the normal summary.
- **`reusable_pass`** → *"Use your existing day pass (from Jul 8) for Jul 10?"* → **Use my pass & book** / **Cancel**.
- **`bundle_available`** → *"This booking uses 1 of your N day passes for Jul 8."* → **Use a pass & book** / **Cancel**.
- **`needs_purchase`** → *"This room needs a day pass for Jul 8 — $Y."* → **Buy day pass & book** / **Cancel**.

Each variant shows the **overage as its own line** when applicable (*"+ $X meeting-room overage (Y min over your included Z min)"*). **Cancel** creates nothing. Paid rooms use the existing paid-room price flow.

## Cancellation

- **Bundle-covered** → restored on cancel when the day is wholly future and the pass is unused, via the existing `restore_redeemed_bundle_passes` (fires because `CommitCoverage` uses `RedeemBundlePass`, `kind:"reservation"`). **Sibling-booking guard:** do NOT restore/refund a day another active `include_with_day_pass` reservation (or a door entry) that day still relies on — verify the existing restore honors this and tighten it if not.
- **Purchased / reused** → **not refunded**; on cancel the pass keeps its (now-cancelled) `reservation_id`, so if unused and `day >= today` it is exactly the **reusable pass** the next booking's `CoverageState` will find and offer to move.
- The reservation's own charge (an overage) refunds per ADR 0011; the separate day-pass purchase stays.

## Edge cases

- **Multiple included bookings, same day:** first commits the pass; later ones are `:already_covered` but still draw the day's included minutes (can show "+ overage").
- **Already-covered overage:** subscription/existing-pass bookings over their allowance charge overage via existing metered rules.
- **No payment method** for a required buy or overage → existing "please provide payment method" failure.
- **Edit/extend:** minutes change re-prices overage (existing path). **Date change is out of v1** — moving a booking to another day = cancel + rebook (so coverage re-commits cleanly).
- **Demo operators** (`billing_state != "production"`) follow existing $0 gating (`should_charge_for_reservation?`).

## Docs / ADR

- **New ADR 0019** — "Included-room booking commits day-pass coverage": commitment-requires-coverage, confirm-before-booking, block-if-uncovered, the four commit paths (reuse → burn → buy → covered), overage independent of coverage source, purchased-kept-and-reusable / bundle-restored on cancel. Builds on ADR 0015; references 0010/0012/0013/0018.
- **CONTEXT.md** — extend the reservation + day-pass sections with the coverage requirement, the commit paths, the reusable-pass concept, and overage independence.

## Testing

- **`CoverageState`** — the 5 outcomes, precedence (`reusable → bundle → purchase`), date-awareness, paid-room carve-out, and `:reusable_pass` detection (a purchased pass with a *cancelled* `reservation_id` qualifies; one tied to an *active* reservation, or a bundle-sourced pass, does not).
- **Overage** — a booking over included minutes charges overage whether covered by bundle / purchase / existing pass; cumulative same-day draw-down; 15-min rounding at the location rate; unlimited type ⇒ no overage.
- **`CommitCoverage`** — reuse (re-dates the spare pass + links it), burn (`kind:"reservation"`), buy (rollback voids the purchase on later failure), no-op for covered/paid, and `fail!`/422 when a decision is required but absent. Ordering test: coverage committed before `ChargeAtBooking`.
- **Cancellation** — bundle restore with the **sibling-booking guard**; purchased kept → becomes reusable; reservation-charge refund per ADR 0011.
- **Request tests** — create with each decision flag; 422 on an uncovered included room with no decision; paid room unaffected; eligibility endpoint returns coverage + overage.
- **Mobile jest** — a pure helper mapping `(coverage state, overage)` → confirm copy/buttons.

## Non-goals / future work

- Date-change re-coverage on edit (v1: cancel + rebook).
- Applying more than one spare pass in a single booking.
- Operator-configurable auto-burn vs confirm.
