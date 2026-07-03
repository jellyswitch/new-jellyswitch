# Phase 1 — Pricing + kill the comp pass (reservation billing redesign)

Self-contained execution brief. A fresh session can execute this from zero. TDD (RSpec). Backend auto-deploys on merge to main. Additive, reversible migrations. **Independent of capture-at-booking (Phase 2)** — this phase alone ends the "Brad bug" (wrong charge on edit/room-switch). See ADRs 0010–0014 and CONTEXT.md (already on main via PR #530).

## Goal / invariants
Make `ChargeCalculator` the single pricing authority with ONE rule for non-exempt bookers (member / leaseholder / staff / admin stay exempt and untouched):
- `room.hourly_rate_in_cents > 0` → charge `rate × minutes`. **Never** the day-pass overage branch.
- `room.hourly_rate_in_cents == 0` → charge the **Location** overage rate × minutes, **minus** the day-pass included allowance. **A $0 room with no day-pass coverage still charges this** (today it falls through to free).
- Demo safety: every charge path stays behind `should_charge_for_reservation?` + `billing_state == "production"`.

## Files & exact changes
1. **Migration** `add_overage_rate_to_locations`: `add_column :locations, :overage_rate_in_cents, :integer, null: false, default: 0`. Data: backfill each location from the max/most-common `day_pass_types.overage_rate_in_cents` for that location's operator (or just leave 0 and have operators set it; confirm with user — default 0 is safe/additive).
2. **Migration** `add_include_with_day_pass_to_rooms`: `add_column :rooms, :include_with_day_pass, :boolean, null: false, default: false`; then a data step setting `include_with_day_pass = true WHERE hourly_rate_in_cents = 0` so existing behavior is preserved. (Default false + backfill, OR default via a model method — but a real column is clearest for the operator UI later.)
3. **`app/models/room.rb`**: `include_with_day_pass` is the new column. Add `def counts_toward_day_pass?; include_with_day_pass?; end` if helpful. `paid_room?` (line ~200) stays.
4. **`app/models/location.rb`**: `overage_rate_in_cents` column. Add reader used by ChargeCalculator.
5. **`app/services/billing/reservations/charge_calculator.rb`** (base_room_or_overage ~43, day_pass_overage_cents ~67, subscription_overage_cents ~83):
   - `base_room_or_overage`: keep `rate > 0 → rate × minutes`. For `rate == 0`, charge the location overage minus the day-pass allowance — AND charge even when there is no day_pass (use the location rate for the uncovered minutes). Today the `else` only charges when a day_pass/sub exists; extend so an uncovered $0-room booking is charged at the location rate.
   - `day_pass_overage_cents`: replace the implicit `rooms.hourly_rate_in_cents = 0` filter (~line 72) with `rooms.include_with_day_pass = true`; read the per-minute rate from the **location** `overage_rate_in_cents` (not `day_pass.day_pass_type.overage_rate_in_cents`).
   - `subscription_overage_cents`: **UNCHANGED** (documented asymmetry — keeps `rate==0` filter and `plan.overage_rate_in_cents`). Member billing must not change.
6. **`app/models/concerns/permissions.rb`** (should_charge_for_room? ~37, should_charge_for_reservation? ~22): resolve the disagreement so a **priced room always charges at its hourly rate and never enters the day-pass overage branch**. Concretely: paid rooms (`rate>0`) price at the room rate regardless of day-pass status; `should_charge_for_reservation?` (day-pass exempt) gates ONLY the $0/overage path + amenity rate selection. Verify `day_pass_reservation_charge_info` (~320) and the create-path quotes agree.
7. **Remove `GrantFreeDayPass` for paid-room bookings**: find the create organizer (reservations create flow) that calls `GrantFreeDayPass`; remove it for paid rooms (and generally — paid bookings mint no comp pass). Building access for paid-room bookers comes from the Phase 4 access window; Phase 1 can ship the removal because the existing all-day-reservation door grant (`user_can_access_building?`) still covers them until Phase 4 tightens it. **Order: Phase 1 (remove comp pass) is safe before Phase 4 only because the all-day reservation grant still lets them in. Document this.**
8. **Operator settings UI**: the overage rate field — relabel to **"Overage / add-on meeting room time"** and move it to the **location** settings (it currently lives on day_pass_type). `app/views/operator/settings/` + `operator/settings_controller.rb` permit `:overage_rate_in_cents` on location. Keep day_pass_type.overage_rate_in_cents readable for back-compat or drop after migration (confirm).
9. **Per-room `include_with_day_pass` toggle** in the room edit UI (operator) — additive checkbox, label "Counts toward day pass (call room)".

## Comp-pass prod cleanup (runs WITH this phase, AFTER deploy)
After P1 deploys, purge active comp `DayPass` rows that the old `GrantFreeDayPass` minted on paid bookings so they can't poison an edit. They're dated and age out at day rollover anyway; a targeted script: find DayPasses with `day >= today`, `imported`/comp-flagged or matching the GrantFreeDayPass signature (free `DayPassType`), whose user has a paid reservation the same day → destroy. **Write as a rake task / runner; user runs it post-deploy.** Confirm exact identifying signature against the GrantFreeDayPass code before deleting.

## TDD test list (write first, RED → GREEN)
- ChargeCalculator: paid room → `rate × minutes` (never overage); $0 room within allowance → 0; $0 room over allowance → location overage × over-minutes; **$0 room, NO day pass / no coverage → location overage × minutes** (the new charge); demo operator → 0; member/lease/staff → 0.
- Regression (Brad): a user with no comp pass booking/editing a paid room re-prices at the room rate, never the day-pass overage branch.
- Subscription overage path UNCHANGED (snapshot a before/after example).
- `GrantFreeDayPass` no longer runs on a paid-room create (assert no DayPass minted).
- Migration reversibility.

## Gotchas / risks
- Keep the subscription overage filter on `rate==0` (don't accidentally switch it to include_with_day_pass) — that would change member billing.
- The "$0 room, no coverage charges location rate" is genuinely new behavior — make sure it's gated by `should_charge_for_reservation?` so exempt members and demo operators are unaffected.
- Multi-agent repo: work in an isolated worktree off origin/main (this branch). Local tree may be on a foreign branch.
- Verify the GrantFreeDayPass call site and the comp-pass signature before writing the cleanup (don't delete legitimate free day passes a member actually bought/was granted for another reason).

## Ships how
Backend auto-deploys on merge to main. Phase 1 is independent; merge it before/independent of Phase 2. Comp-pass cleanup is a manual post-deploy step. Next: Phase 2 (capture-at-booking) reuses this ChargeCalculator as the single authority.
