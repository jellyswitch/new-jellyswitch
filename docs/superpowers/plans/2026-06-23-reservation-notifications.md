# Phase 6 — Reservation notifications (reservation billing redesign)

Self-contained execution brief. TDD (RSpec + Minitest). Backend auto-deploys on merge. Realizes the notification half of the redesign (ADR 0013 already says the "come back ~N min before" push reads `Operator#building_access_window_minutes`). Branch `feat/reservation-notifications` (stacked on Phase 5 → 4 → 2 → 1).

## Goal — three member-facing reservation pushes
1. **Come-back / arrival** — fires at `datetime_in − building_access_window_minutes`, telling the booker their door access is open. Reads the **same** operator column the door uses (Phase 4) so the promise can't drift. **Replaces** the existing hardcoded "starts in 15 minutes" booker reminder (one pre-start booker push, now access-aware — no double-push).
2. **Started** — fires at `datetime_in` ("your room is ready / booking has started"). Scheduled only when the access window is ≥ 15 min so it doesn't collide with the come-back push.
3. **Charge** — a member-facing push on a successful capture, alongside the existing receipt email (`UserMailer.meeting_room_charged`). Capture path only (net-30 `send_invoice` stays silent — Stripe emails its own invoice).

## Push primitive (reuse — from the surface map)
`SendNotificationsJob.perform_now/later(reservation, "<Type>")` → `NotifiableFactory.for` → `Notifiable::<Type>` (subclass of `Notifiable::Default`, a `SimpleDelegator` over the reservation). A new type needs: a `when` branch in `app/object_factories/notifiable_factory.rb` + an adapter implementing `message`, `recipients` (`[user]`), `should_send_notification?` (`true`), `create_feed_item` (no-op), `deep_link_data`. Deep link for booker pushes: `{ screen: "MyReservations", type: "reservation", resource_id: id }`. Sends no-op without a device token / operator push config (built-in). No billing_state gate on pushes (timed pushes are not money; the charge push hangs off the already-demo-gated capture path).

## Files & changes
1. **`app/interactors/reservations/schedule_upcoming_reservation_reminder.rb`**:
   - Replace the booker reminder (line 16: `datetime_in − 15.minutes`) with `arrival_at = datetime_in − window.minutes` where `window = reservation.room.location.operator.building_access_window_minutes || 60`; schedule `SendReservationReminderJob` at `arrival_at` if future.
   - Add a started job: schedule `SendReservationStartedJob` at `datetime_in` **only if** `window >= 15` (avoid collision with come-back).
   - Leave the prior-occupant + meeting-ending schedules untouched.
2. **`app/jobs/send_reservation_reminder_job.rb`** (repurposed as the arrival/come-back push): window-aware self-guard — re-derive `arrival_at = start_at − window.minutes`; fire only if `Time.current >= arrival_at − GRACE(2min) && Time.current < start_at` (a moved booking's stale job self-skips). Still bail on nil/cancelled. Dispatch `"ReservationReminder"`.
3. **`app/adapters/notifiable/reservation_reminder.rb`**: message → access-aware, e.g. `"You can get into #{room.location.name} now — your #{room.name} booking starts at #{...}."` Keep `recipients [user]`, deep link, `should_send_notification? true`.
4. **NEW `app/jobs/send_reservation_started_job.rb`**: fire at start — guard `now >= start_at − GRACE && now < datetime_out` && not cancelled; dispatch `"ReservationStarted"`.
5. **NEW `app/adapters/notifiable/reservation_started.rb`**: message `"Your #{room.name} booking has started."`, booker recipient, deep link.
6. **NEW `app/adapters/notifiable/reservation_charged.rb`**: message `"You were charged #{$amount} for #{room.name} on #{date}."` (format like `paid_room_reservation.rb`), booker recipient, deep link.
7. **`app/object_factories/notifiable_factory.rb`**: register `"ReservationStarted"` + `"ReservationCharged"` (`"ReservationReminder"` already present).
8. **`app/interactors/billing/reservations/charge_at_booking.rb`**: best-effort `SendNotificationsJob.perform_later(reservation, "ReservationCharged")` beside `send_receipt` (post-capture path only; rescued). Idempotent via the existing `captured_at` early-return.
9. **`app/interactors/billing/reservations/charge_extension_delta.rb`** — DEFERRED (fast-follow). A push here must show the **delta** just charged, but the `ReservationCharged` adapter reads `captured_amount_in_cents`, which the extension path sets to the **cumulative** total — so a naive dispatch would announce the wrong (inflated) amount. Doing it right needs the charged amount threaded through `SendNotificationsJob`/the adapter, and a product call on delta-vs-total wording. The extension already sends a receipt email; the push is a separate small follow-up. Not in this PR.
10. **`app/interactors/billing/reservations/update_billing_and_create_room_reservation.rb`**: add `Reservations::ScheduleUpcomingReservationReminder` (the new-card booking path currently schedules NO timed reminders — gap found in the map) so all bookings get the arrival/started pushes.

## TDD test list
- Scheduler: schedules the arrival job at `datetime_in − window` (not 15 min); schedules started at `datetime_in` when window ≥ 15, and NOT when window < 15. (Mocha `.expects(:set).with(wait_until:)` per the repo convention.)
- Arrival job: fires `ReservationReminder` inside the window; self-skips for a cancelled / moved-later / already-started reservation.
- Started job: fires `ReservationStarted` at start; skips cancelled / ended / not-yet-due.
- Charge push: `ChargeAtBooking` (self-serve capture) dispatches `ReservationCharged`; out_of_band/demo/exempt → no push (rides the existing early-returns). (Extension-delta charge push deferred — see file note 9.)
- Adapters: `ReservationReminder` message reads the operator window; recipients = `[user]`; deep link keys present.
- New-card organizer includes the scheduler step.

## Gotchas
- Read the window the SAME way the door does (`room&.location&.operator&.building_access_window_minutes || 60`) so message + door never diverge.
- Edits don't cancel old jobs — rely on the window self-guards (existing convention; no `*_notified_at` column).
- Don't add the charge push to the net-30 `send_invoice` path.
- Keep new member pushes unconditional (`should_send_notification? true`), matching the existing booker reminder; `operator.reservation_notifications?` gates only the ADMIN booking push.

## Ships how
One PR, stacked on Phase 5. Don't merge without the user's go. The mobile already deep-links reservation pushes (jellyswitch-mobile #84/#87); the two-audience UX is Phase 7.
