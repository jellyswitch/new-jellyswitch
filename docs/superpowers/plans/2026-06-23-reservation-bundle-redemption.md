# Phase 5 — Reserve-time bundle redemption (reservation billing redesign)

Self-contained execution brief. TDD (RSpec + Minitest). Backend auto-deploys on merge. Implements **ADR 0015**. Branch `feat/reservation-bundle-redemption` (stacked on Phase 4 → Phase 2 → Phase 1).

## Goal
A Day Pass **Bundle** holder booking a $0 (call) room may **opt in** ("use 1 pass for today") to cover it with one prepaid bundle pass — minting a `DayPass` (so pricing/access treat it like a day pass: free $0 rooms + included minutes, never paid rooms), burning exactly **one pass per business-day period**, reconciled with the door's burn-on-entry so they never double-burn.

## Key facts (from the surface map)
- Bundles are invisible to pricing — `ChargeCalculator`/gates only see `DayPass`+`Subscription`. Coverage requires **minting a `DayPass`**. `ConsumeOnEntry` (`app/interactors/billing/day_pass_bundles/consume_on_entry.rb:68-78`) is the template: `DayPass.create!(..., imported: true)` then `bundle.burn_locked!(...)`.
- `DayPassBundle#burn_locked!(kind:, performed_by:, guest_name:, day_pass:)` (`day_pass_bundle.rb:34-40`) — assumes caller holds `with_lock`; decrements + creates a `DayPassBundleRedemption`.
- Reconciliation token = the minted `DayPass`. `ConsumeOnEntry` Guard 4 (`:34-37`) returns `:already_covered` when `user.day_passes.for_location(location).for_day(today).exists?` — runs **before** its `kind:"entry"` window dedupe, so a reservation-minted pass stops the door burn regardless of redemption `kind`. (Guard 3 also suppresses the door burn when a reservation exists that day.)
- Member API `app/controllers/api/v1/reservations_controller.rb#create` **auto-purchases** a day pass for uncovered $0 bookings (`:44-87`, `needs_cov`). A bundle holder hits this and gets charged for a fresh pass — Phase 5's opt-in must redeem instead.
- Create organizers (post-Phase-2): `CreateRoomReservation` = Save → ChargeCredits → ChargeAtBooking → …; `UpdateBillingAndCreateRoomReservation` = UpdateUserPayment → Save → ChargeAtBooking → … (no ChargeCredits).
- `ChargeAtBooking` no-ops when `ChargeCalculator` returns 0 (`charge_at_booking.rb:24-29`).

## Files & changes
1. **Migration** `add_reservation_to_day_pass_bundle_redemptions`: `add_reference :day_pass_bundle_redemptions, :reservation, null: true, index: true`. Additive/reversible.
2. **`app/models/day_pass_bundle_redemption.rb`**: `KINDS = %w[entry guest admin_restore reservation]`; `belongs_to :reservation, optional: true`.
3. **`app/models/day_pass_bundle.rb`**: `burn!` and `burn_locked!` accept optional `reservation: nil`, passed to `redemptions.create!`. `enqueue_lifecycle_emails` unchanged (only fires "follow_up" on the first `entry` burn — a reservation burn won't, which is fine).
4. **NEW `app/interactors/billing/reservations/redeem_bundle_pass.rb`** (`include Interactor`, `delegate :reservation, :user, :use_bundle_pass, to: :context`):
   - `return unless use_bundle_pass` (opt-in).
   - `room = reservation.room; return if room.hourly_rate_in_cents.to_i > 0` (paid rooms never covered).
   - `location = room.location; day = reservation.datetime_in.to_date`.
   - `return if user.day_passes.for_location(location).for_day(day).exists?` (already covered — no burn).
   - `bundle = user.day_pass_bundles.active.where(location: location).first; return unless bundle` (no bundle → fall through to pricing).
   - `bundle.with_lock do` re-check day-pass-exists (race), then mint `DayPass.create!(user:, billable: user, operator: bundle.operator, location:, day_pass_type: bundle.day_pass_type, day:, imported: true)` + `bundle.burn_locked!(kind: "reservation", performed_by: user, day_pass:, reservation:)`. Store `context.bundle_redemption_day_pass` + `context.redeemed_bundle` for rollback. `rescue DayPassBundle::NoPassesRemaining` → no-op (log; pricing will charge).
   - `#rollback`: if a pass was burned, destroy the minted `DayPass` + its redemption and `passes_remaining += 1` (direct reversal, not `restore!` — avoid an admin_restore audit row for a never-committed booking).
5. **Both organizers**: insert `Billing::Reservations::RedeemBundlePass` after `SaveRoomReservation`, before `ChargeAtBooking`.
6. **Member API `#create`**: read `use_bundle_pass = ActiveModel::Type::Boolean.new.cast(params.dig(:reservation, :use_bundle_pass))`; add to `needs_cov`: `&& !(use_bundle_pass && user.has_active_day_pass_bundle?(location))` (skip auto-purchase when opting in with a bundle); pass `use_bundle_pass: use_bundle_pass` into `CreateRoomReservation.call`/`UpdateBillingAndCreateRoomReservation.call`.
7. **Cancel-restore** in `app/interactors/cancel_reservation.rb`: after a successful cancel, find `reservation` redemptions (`DayPassBundleRedemption.where(reservation_id: reservation.id, kind: "reservation")`); for each, if `Time.current < reservation.room.location.business_day_window(reservation.datetime_in).first` (coverage day not started) → `bundle.with_lock { passes_remaining += 1 }`, destroy the minted `DayPass` + the redemption. Else leave (spent). Best-effort (rescue + Honeybadger), never fail the cancel.

## TDD test list
- **RedeemBundlePass**: opt-in + $0 room + active bundle → mints a DayPass(imported), burns 1 pass, redemption(kind:"reservation", reservation_id set); ChargeCalculator then returns 0. Not opted in → no-op. Paid room → no-op (pass not burned). Already has a DayPass that day → no-op (no second burn). No active bundle → no-op. Rollback restores the pass + destroys the minted pass.
- **Reconciliation**: reserve-time redeem today, then `ConsumeOnEntry` → `:already_covered`, `passes_remaining` unchanged (no double-burn). And the reverse (door first → reserve-time no-op).
- **One per period across days**: two $0 reservations same business-day → one pass burned.
- **Member API**: `use_bundle_pass: true` with a bundle skips auto-purchase and books free, burning one pass; without the flag, behavior unchanged.
- **Cancel-restore**: cancel a future-dated redeemed reservation before its day → pass restored, minted DayPass gone; cancel one whose day has started → pass stays spent.
- **Migration** reversibility.

## Gotchas
- Order matters: redemption must run AFTER Save (validated reservation) and BEFORE ChargeAtBooking (so the minted pass zeroes the charge). Rollback must undo the burn if a later step fails.
- The member controller auto-purchase MUST be skipped when opting in, or the member is charged for a fresh day pass instead of using their bundle.
- Dedupe on "DayPass for that date exists", not the `redeemed_at` window — the window is current-period-only and breaks for future-dated reservations; the minted DayPass reconciles across days via Guard 4.
- Do NOT widen `ConsumeOnEntry`'s `kind:"entry"` window dedupe — Guard 4 (minted DayPass) already prevents the door double-burn. Add a test proving it.
- Demo: no gate on the burn (prepaid); the pricing path already no-charges in demo.

## Ships how
One PR, stacked on Phase 4. Don't merge without the user's go. Mobile "use 1 pass for today?" prompt is Phase 7 (this only adds the backend opt-in param + mechanism).
