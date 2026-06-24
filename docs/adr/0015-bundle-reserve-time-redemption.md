# Reserve-time bundle redemption mints a day pass, one pass per business-day period

A Day Pass **Bundle** holder booking a $0 (call) meeting room may **opt in** ("use 1 pass for today") to cover the reservation with one prepaid bundle pass. Redemption **mints a `DayPass`** for the reservation's date (the same `imported: true` artifact `ConsumeOnEntry` mints on door entry) and burns one bundle pass, recording a `DayPassBundleRedemption(kind: "reservation")` linked to the reservation. The minted day pass is what makes the booking free and grants access — the pricing/permission layer recognizes bundles only via a `DayPass`, never the bundle directly.

## Context

Bundles are invisible to pricing: `ChargeCalculator` and the charge gates check `DayPass` and `Subscription` rows, not bundles (a bundle grants door access only, via `has_active_day_pass_bundle?`). So a bundle holder booking a $0 room with no day pass is charged the location overage (Phase 1), and the member booking API "closes the gap" by **auto-purchasing** a fresh day pass — charging a bundle holder for a new pass they shouldn't need. Burn-on-entry (`ConsumeOnEntry`) already mints a `DayPass` + a `DayPassBundleRedemption(kind: "entry")`, deduped once per **business-day window** (4am rollover, `Location#business_day_window`).

## Decision

- **Opt-in only** (`use_bundle_pass: true`). A member with a bundle is never silently drained — they may have booked free anyway, or want to save passes.
- **Mint a `DayPass`** for `reservation.datetime_in.to_date` (type = bundle's `day_pass_type`, `imported: true`), then `burn_locked!` one pass inside the bundle row lock. The minted pass makes `ChargeCalculator` return 0 for a within-allowance $0 room → `ChargeAtBooking` no-ops. **Priced rooms are never covered** — `should_charge_for_room?` ignores day passes, so RedeemBundlePass no-ops for `hourly_rate_in_cents > 0`.
- **One pass per business-day period**, reconciled with the door via the **minted `DayPass`**: the dedupe is "does a `DayPass` for that location+date already exist?" (`ConsumeOnEntry` Guard 4 / the same predicate). This works *across days* (future-dated reservations) where a `redeemed_at`-window check would not, and means the door never double-burns — `ConsumeOnEntry` Guard 4 short-circuits on the minted pass before it reaches its `kind: "entry"` window check, so the new `kind: "reservation"` needs no widening of the door dedupe.
- **Hook as an organizer step** `Billing::Reservations::RedeemBundlePass`, after `SaveRoomReservation` (reservation validated + persisted) and before `ChargeAtBooking` (so the minted pass zeroes the charge), in both create organizers. The member API skips its auto-purchase block when opting in with an active bundle. Rollback restores the pass + destroys the minted pass if a later step fails.
- **Cancel-restore**: cancelling a reservation whose pass was redeemed restores the pass and destroys the minted day pass **only if the reservation's business-day window has not started** (purely future, coverage unused). Same-day/past cancels keep the pass spent (the day's access was live). Requires the `redemptions.reservation_id` link.

## Consequences

- **Additive migration**: `day_pass_bundle_redemptions.reservation_id` (nullable) + `kind: "reservation"` added to `KINDS`. `burn!/burn_locked!` accept an optional `reservation:`.
- No demo gate on the burn (a prepaid pass is state-agnostic); the demo gate rides the pricing path (no charge in demo) as before.
- Bundle revenue is still recognized once at sale (ADR 0009) — the minted pass is `bundle_sourced`/`imported`, excluded from day-pass revenue.
- The non-opted-in path is unchanged (a bundle holder who doesn't opt in still hits the existing auto-purchase / overage behavior). The mobile two-audience UX (Phase 7) surfaces the opt-in.
