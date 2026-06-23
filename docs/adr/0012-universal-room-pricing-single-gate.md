# Universal room pricing: one gate, per-room day-pass inclusion, location overage

For any booker who is **not** exempt (member / leaseholder / staff / admin — those stay free), room pricing follows one rule:

- **Room with `hourly_rate_in_cents > 0` (a Meeting room)** → charged at its **own hourly rate × minutes**, captured at booking. It never enters the day-pass overage branch.
- **Room with `hourly_rate_in_cents == 0` (a Call room)** → charged at the **Location** "Overage / add-on meeting room time" rate × minutes, **minus** the booker's Day Pass included allowance. A $0 room booked with **no** day-pass coverage still charges this rate (it no longer falls through to free).

Whether a room counts toward the day-pass bucket is the new per-room boolean **`rooms.include_with_day_pass`** (default: `true` when the rate is $0, `false` when > 0 — preserving today's behavior). The overage rate moves from `day_pass_type.overage_rate_in_cents` up to **`locations.overage_rate_in_cents`**. **`GrantFreeDayPass` is removed for paid-room bookings** (no comp pass is ever minted). Subscription overage (`plan.overage_rate_in_cents`, `subscription_overage_cents`) is **unchanged**.

## Context

Two permission gates disagreed by design: `should_charge_for_room?` (day-pass holders **not** exempt) and `should_charge_for_reservation?` (day-pass holders exempt). `ChargeCalculator#day_pass_overage_cents` selected the day-pass bucket implicitly via `rooms.hourly_rate_in_cents = 0`, and `GrantFreeDayPass` minted a complimentary `DayPass` on paid bookings whose `included_meeting_room_minutes` then re-priced a later edit through the overage branch — the "Brad bug" ($35 paid room captured as a discounted day-pass rate after a room switch). A $0 room booked with no coverage also went free.

## Decision

Make `ChargeCalculator` the single pricing authority with the universal rule above. Resolve the gate disagreement so a priced room **always** prices at its hourly rate and never the overage branch. Replace the implicit `rate == 0` bucket filter with `include_with_day_pass`. Lift the overage rate to the Location so it applies to bookers with no day pass (e.g. a group adding a $0 breakout room). Delete `GrantFreeDayPass`; paid-room bookers get building access from the Access window (ADR 0013), not a comp pass.

## Consequences

- **Two additive, reversible migrations**: `locations.overage_rate_in_cents` and `rooms.include_with_day_pass` (existing day-pass-type overage values migrate up to the location).
- **Invariant**: `rate > 0` never enters the overage branch.
- **Documented asymmetry**: the **subscription** overage path keeps its `rate == 0` filter unchanged, so this redesign does not touch member billing.
- The new "$0 room with no coverage charges the location overage" stays behind `should_charge_for_reservation?` and the `billing_state` gate, so exempt bookers and demo operators are unaffected.
- **Existing comp Day Passes in prod** (minted by the old `GrantFreeDayPass`) can still poison an edit until they age out at day rollover — a one-time cleanup runs with this phase.
