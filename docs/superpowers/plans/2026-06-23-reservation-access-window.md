# Phase 4 — Reservation access window (not all-day) (reservation billing redesign)

Self-contained execution brief. TDD (RSpec + Minitest). Backend auto-deploys on merge. Implements **ADR 0013**. Branch `feat/reservation-access-window` (stacked on Phase 2; only depends on Phase 1's comp-pass removal — independent of Phase 2's capture changes).

## Goal (ADR 0013)
A reservation grants building access **only inside an Access window** around its slot: from `Operator.building_access_window_minutes` before start to the same after end (default 60). Outside that window the reservation grants no access. A booker with only a paid Meeting-room reservation (no Day Pass / membership / lease) gets access **solely** from this window. Day Pass, membership, lease, bundle, admin access unchanged.

## Current state
`Api::V1::DoorUnlocking#user_can_access_building?` (app/controllers/concerns/api/v1/door_unlocking.rb:6) grants access for **any** non-cancelled reservation *that day* (all-day): it queries `reservations.where(datetime_in: today.beginning_of_day..end_of_day).any?`. Booking a 3pm room lets you in at midnight. (`allowed_in?` in permissions.rb already uses `ongoing?` — the exact slot — so it's not all-day and is left as-is.)

`Reservation#datetime_in` / `#datetime_out` are absolute instants (timestamptz), so a `±window` instant comparison is zone-correct by construction.

## Files & changes
1. **Migration** `add_building_access_window_minutes_to_operators`: `add_column :operators, :building_access_window_minutes, :integer, null: false, default: 60`. Additive/reversible.
2. **`app/models/reservation.rb`**: `access_window_open?(at = Time.current, window_minutes: nil)` → `window = (window_minutes || room&.location&.operator&.building_access_window_minutes || 60).minutes; (datetime_in - window) <= at && at <= (datetime_out + window)`. (window_minutes arg lets the door path avoid an N+1 on operator.)
3. **`app/controllers/concerns/api/v1/door_unlocking.rb`**: replace the all-day reservation query with: read `window_minutes = location&.operator&.building_access_window_minutes || 60`; candidate query `reservations.where(cancelled: false).where(datetime_in: (now - 1.day - window)..(now + 1.day + window))` (coarse, catches midnight spillover); then `.any? { |r| r.access_window_open?(now, window_minutes: window_minutes) }` (exact decision in Ruby). The other callers (doors_controller, auto_unlocks_controller, dashboard_controller) use this same method → windowed automatically.
4. **Operator UI**: add `building_access_window_minutes` to Settings → Doors (view field + `doors_params` permit on operator). Label: "Door access window around a reservation (minutes)". Phase 6's "come back ~1hr before" push reads the same column.

## TDD test list
- `Reservation#access_window_open?`: true during the slot; true within window before start; true within window after end; false before the window opens; false after it closes; honors a custom operator window.
- `user_can_access_building?` via `doors_controller_test` (manual unlock): non-member with a reservation **now** → 200 (door unlocks); non-member with a reservation **3 days out** → 403; non-member with a reservation starting in ~30 min (default 60 window) → 200. Member / lease / day-pass paths unchanged (existing tests stay green).
- Migration reversibility.

## Gotchas
- Compare absolute instants (`datetime_in`/`datetime_out` are timestamptz) — no zone math needed for the window itself; the coarse candidate query just needs to be wide enough (±(1 day + window)) so the Ruby filter sees every relevant row.
- Only change `user_can_access_building?` (the documented all-day grant). Leave `allowed_in?`'s `ongoing?` clause (already slot-exact).
- Members/leaseholders must stay unaffected — their access comes before the reservation branch.

## Ships how
One PR, stacked on Phase 2 (retarget to main after the stack merges). Independent of capture-at-booking; needs Phase 1's comp-pass removal so paid-room bookers rely on the window, not a comp pass. Don't merge without the user's go.
