# Phase 2 — Capture at booking + cancellation/refunds (reservation billing redesign)

Self-contained execution brief. A fresh session can execute this from zero. TDD (RSpec + Minitest). Backend auto-deploys on merge to main. **Builds on Phase 1** (branch `feat/reservation-billing-phase-2-capture` off `feat/reservation-billing-phase-1-pricing`; ChargeCalculator is already the single pricing authority). See ADR 0010 (capture-at-booking) and ADR 0011 (cancellation/refunds) — both already on the branch.

## Why these two ship together
ADR 0010: capturing at booking means far-future bookings **take money today** — there is no longer a "free hold release," so cancellation becomes a **refund**. ADR 0010 explicitly states the cancellation/refund policy (ADR 0011) ships in the **same release**. → **One PR, atomic.** ADR 0013 (access window, Phase 4) is NOT required here: Phase 1 removed the comp pass but kept the all-day reservation grant (`allowed_in?` → `has_active_reservation?`), so paid-room bookers still get in until Phase 4 narrows it.

## Goal / invariants
- A paid reservation's charge (`ChargeCalculator`) is **captured at booking**, with the local Invoice committed at the same moment. Self-serve → immediate-capture PaymentIntent; net-30 `out_of_band` orgs → Stripe `send_invoice` (NEW — they currently book rooms free).
- Exempt bookers (member/leaseholder/staff) and **demo operators** (`billing_state != "production"`) move no money — every money path stays gated.
- `captured_at` stamps **on success only** and is the idempotency marker (`ChargeAtBooking` is a no-op if set). Idempotency keys (reservation id + amount) on every Stripe charge.
- Booking is synchronous: a card decline **fails the booking** and `SaveRoomReservation#rollback` destroys the reservation (no phantom slot).
- A cancel **refunds**: inside the cancellation window → forfeit (no refund); outside → refund minus `refund_fee_percent`; no-show → charge stands. **All** of a reservation's invoices are refunded (extensions add more). One pipeline for member/admin/web cancels.

## Current state (what we're replacing) — file:line
- Booking: `CreateRoomReservation` / `UpdateBillingAndCreateRoomReservation` organize `AuthorizeHoldOrSchedule` (immediate `AuthorizeHold` within 6 days, else defer to `AuthorizeReservationHoldJob`) + `ScheduleSettleReservation` → `SettleReservationJob` at `datetime_in` → `CaptureHold` (captures `min(actual, authorized)`, creates Invoice/FeedItem/receipt).
- Edit (`UpdateRoomReservation`): re-prices via `AuthorizeHoldOrSchedule` (`is_extend`), reschedules settle. Controller `#update` blocks when `captured_at.present?`.
- Extend (`ExtendReservation`): post-start → `ChargeExtensionDelta` (immediate-capture for the delta); pre-start → `AuthorizeHoldOrSchedule`.
- Cancel (member API `Api::V1::ReservationsController#destroy` ~172-249): window/fee logic captures a **partial** of the hold (inside → forfeit/full capture; outside → capture fee%), else voids the PI. **No Invoice refund.** 1-min `CANCEL_CUTOFF`.
- Cancel (admin API `Api::V1::Admin::ReservationsController#destroy` ~105-153): if captured → `Refunds::Create.call(invoice: RefundableFactory.for(invoice))` for the **single** invoice keyed by `reservation.stripe_payment_intent_id`; else voids PI.
- Cancel (web `Operator::ReservationsController#destroy`): `CancelReservation` (just sets `cancelled = true`).
- Refund pipeline (REUSE): `Billing::Invoices::Refunds::Create` → `Save` → `invoice.cancel` on adapter. `RefundableFactory.for(invoice)` → `RefundableInvoice` (paid) / `VoidableInvoice` / `NotRefundable`. `RefundableInvoice#refundable_amount_in_cents` **already retains `operator.refund_fee_percent`**; `#refund_payment_intent` already does `Stripe::Refund.create` against the reservation PI. **This is why "outside window" = just call the pipeline.**
- Money primitive to mirror: `Billing::Reservations::ChargeExtensionDelta` (auto-capture PI + Invoice + FeedItem + `UserMailer.meeting_room_charged`).
- send_invoice pattern to mirror: `Billing::Invoices::Custom::CreateInvoice` / `Reservable::OutOfBand#invoice_args` (`billing: 'send_invoice', days_until_due: 30`).
- Invoice STATUSES = open/uncollectible/void/paid/refunded. No `reservation_id` today; invoices are polymorphic `billable: User`.

## Files & changes

### A. Migration + association (foundation — SAFE, do first)
1. `add_reservation_id_to_invoices`: `add_reference :invoices, :reservation, null: true, index: true` (no FK constraint needed; or `foreign_key: true` — additive/reversible). Annotate.
2. `app/models/invoice.rb`: `belongs_to :reservation, optional: true`.
3. `app/models/reservation.rb`: `has_many :invoices` (`dependent: :nullify`). Stamp `reservation_id` on every invoice created at booking + extension.

### B. `Billing::Reservations::ChargeAtBooking` (NEW — mirror ChargeExtensionDelta)
- `return` (no charge) if `captured_at.present?` (idempotent) OR `ChargeCalculator.call(reservation:, minutes:) <= 0` (free/exempt/demo — ChargeCalculator already returns 0 for exempt+demo).
- **out_of_band org** → create a Stripe `send_invoice` (net-30) for the amount; local Invoice `status: 'open'`, `due_date: +30d`, `reservation_id`. Stamp `captured_at` (billed marker). (Corrects today's free-room slip.)
- **self-serve** → immediate-capture PaymentIntent (`capture_method: 'automatic', confirm: true, off_session: true`), idempotency key `"resv-#{id}-charge-#{amount}"` in opts. On success: update `reservation.stripe_payment_intent_id`, `authorized_amount_in_cents`, `captured_amount_in_cents`, `paid: true`, `captured_at: Time.current`; create Invoice `status: 'paid'` (`reservation_id`, `stripe_payment_intent_id`); FeedItem (`paid-room-reservation`); `UserMailer.meeting_room_charged`.
- `Stripe::CardError` → `context.fail!` (the organizer rollback destroys the reservation). Stamp `captured_at` ONLY on success.
- Best-effort Invoice/FeedItem/email (rescue+Honeybadger) like ChargeExtensionDelta, BUT the **capture** must hard-fail the booking on card decline.

### C. Rewire booking organizers
- `CreateRoomReservation`: replace `AuthorizeHoldOrSchedule` + `ScheduleSettleReservation` with `ChargeAtBooking`. Keep SaveRoomReservation (its `rollback` already destroys the reservation — verify it fires on ChargeAtBooking failure), ChargeCredits, reminders, notifications, emails.
- `UpdateBillingAndCreateRoomReservation`: replace `AuthorizeHold` + `ScheduleSettleReservation` with `ChargeAtBooking`.
- `SaveRoomReservation`: the overage hold-amount plumbing (`context.overage_charge_amount` from charge_info) becomes irrelevant for the *hold*; ChargeCalculator is the amount. Keep `paid` flag derivation but the real charge is ChargeAtBooking. Verify `should_charge`/payment-method check still guards "no card → fail".

### D. Edit / extend (captured_at is now always set!)
- `Api::V1::ReservationsController#update`: REMOVE the `captured_at.present?` block (it would block every edit now). Keep the 1-min cutoff. Same for admin edit if present.
- `UpdateRoomReservation`: re-price via ChargeCalculator; if `new_total > captured_amount` → charge the delta (reuse `ChargeExtensionDelta`); if `new_total <= captured_amount` → **no refund** (ADR 0011 reductions don't auto-refund). Drop `AuthorizeHoldOrSchedule` + `ScheduleSettleReservation`. Stamp the delta invoice with `reservation_id`.
- `ExtendReservation`: collapse to always `ChargeExtensionDelta` (no pre-start hold branch). Drop the `AuthorizeHoldOrSchedule` path.

### E. Cancellation → unified refund pipeline (ADR 0011)
- `CancelReservation` interactor becomes the single entry: params `reservation`, `mode` (`:member` | `:admin` | `:forced`), `current_user`. Under `with_lock` + `Reservation.unscoped { reload }` (race protection):
  - set `cancelled: true`.
  - **member/web**: compute `inside_window = cancellation_window_hours > 0 && (datetime_in - now) < window.hours`. Inside → forfeit (no refund). Outside → refund **all** `reservation.invoices` via `Refunds::Create.call(invoice: RefundableFactory.for(inv))` (pipeline applies `refund_fee_percent`).
  - **admin/forced**: refund all invoices (consider a no-fee/full mode via the refundable adapter — ADR 0011 "mode (member/admin/forced)"; minimal first pass may reuse the fee'd refund and note the gap).
  - `NotRefundable` null-object means the multi-invoice loop never crashes on already-refunded/void invoices.
- Route member API `#destroy`, admin API `#destroy`, web `#destroy` all through `CancelReservation` with the right mode. Remove the member-cancel partial-capture-of-hold logic (no more hold).

### F. Retire the hold/settle machinery (LAST — after C/D/E)
Delete + remove all references/tests: `AuthorizeHold`, `AuthorizeHoldOrSchedule`, `AuthorizeReservationHoldJob`, `Reservations::ScheduleSettleReservation`, `SettleReservationJob`, `Billing::Reservations::CaptureHold`. Grep clean (Phase-1 map lists every call site).

## TDD test list (write first)
- **ChargeAtBooking**: self-serve paid room → captures amount, `paid: true`, `captured_at` set, Invoice(paid, reservation_id), FeedItem, receipt; idempotent (second call no-op); card decline → `context.fail!` + `captured_at` stays nil; out_of_band → send_invoice + Invoice(open, +30d, reservation_id), no PI capture; demo operator → no money, no Invoice; exempt member → no money.
- **Booking organizer**: card decline destroys the reservation (rollback) — no phantom row holds the slot.
- **Edit**: increasing minutes/price after booking charges the delta; reducing does NOT refund; controller no longer blocks on captured_at.
- **Cancel**: outside window refunds all invoices minus fee (incl. an extension-delta invoice); inside window refunds $0 (charge stands); no-show charge stands; member+admin+web all go through CancelReservation; refund-all loop survives an already-refunded invoice (NotRefundable).
- **Migration** reversibility; `Reservation has_many :invoices`.
- **Retirement**: organizers no longer reference the deleted classes (structural specs).

## Gotchas / risks
- **captured_at is set at booking now** → any guard/branch keyed on `captured_at.present?` flips meaning. Audit: member `#update`/`#destroy`, admin equivalents, ExtendReservation, CaptureHold callers. (This is the #1 footgun.)
- **out_of_band orgs now pay** for reservations + extensions (previously free) — intended (ADR 0010) but a real billing change; call it out in the PR.
- **Refund-all is unsafe until `reservation_id` is stamped** at booking + extension — do A before E.
- **Inside-window forfeit = skip the pipeline** (don't call it with a 100% fee). Outside = call it (fee already applied by RefundableInvoice).
- **Idempotency**: ChargeAtBooking no-op if `captured_at` set; Stripe idempotency key prevents double-charge on retry. The retired CaptureHold stamped captured_at on failure — do NOT replicate that; stamp on success only.
- **Demo gate** on ChargeAtBooking, ChargeExtensionDelta (already), the $0-no-coverage charge (Phase 1), and refunds. ChargeCalculator returning 0 for exempt/demo means ChargeAtBooking naturally no-ops, but assert it.
- **Multi-agent repo**: isolated worktree off the Phase-1 branch.

## Ships how
One atomic PR (capture + cancellation must deploy together). Backend auto-deploys on merge — **do not merge without the user's go.** Sequence on the branch: A (migration+assoc) → B (ChargeAtBooking, green, unused) → C/D/E (the atomic switch + cancel rewire + edit/extend) → F (delete dead machinery) → full suite green. Phase 4 (access window) is a separate follow-up.
