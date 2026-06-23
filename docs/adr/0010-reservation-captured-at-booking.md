# Reservation money is captured at booking, not at start

A **Reservation**'s charge is computed by `ChargeCalculator` and **captured at booking**, with the local **Invoice committed at the same moment** — rather than authorizing a hold at booking and capturing it when the reservation starts. Self-serve bookers are charged via an immediate-capture Stripe `PaymentIntent` (`capture_method: "automatic"`, `confirm: true`, `off_session: true`) for the actual amount; net-30 (`out_of_band`) organizations are billed via a Stripe `send_invoice`. Exempt bookers (member / leaseholder / staff) and **demo operators** (`billing_state != "production"`) move no money.

## Context

The prior model authorized a manual-capture `PaymentIntent` at booking for the *expected max*, deferred the real capture to `SettleReservationJob` at start time, and reconciled `min(actual, authorized)` in `CaptureHold` — which only then created the Invoice. That produced: two independent derivations of the charge (authorize vs settle), a capture-vs-cancel race, the `paid`-vs-PaymentIntent footgun (flipping `paid = false` never stopped a capture), a ~7-day manual-capture expiry that forced a far-future deferral job, and wrong re-pricing on edits. `ChargeCalculator` is already the authoritative amount, and immediate-capture already exists and is proven for extension deltas (`Billing::Reservations::ChargeExtensionDelta`).

## Considered options

- **(a) Keep the hold model, fix its bugs.** Lower churn risk, but preserves two charge derivations, the expiry/deferral machinery, and the `paid`-vs-PI footgun — the operators can't reason about it.
- **(b) Capture at booking via PaymentIntent / send-invoice (chosen).** One charge derivation, no settle/expiry/deferral, `paid` can mean "charged"; reuses the proven extension-delta pattern.
- **(c) Stripe Invoice object for everyone.** Uniform refunds, but charging becomes async (webhook-dependent) and can't synchronously confirm a card the way `confirm: true` does today.

## Why (b)

Removing the hold layer deletes `AuthorizeHold`, `AuthorizeHoldOrSchedule`, `AuthorizeReservationHoldJob`, the 6-day deferral horizon, `ScheduleSettleReservation`, `SettleReservationJob`, `CaptureHold`, and the `min()` reconciliation — far-future and reserve-now collapse into one synchronous path. It aligns reservations with the "recognize once, at collection" precedent already set for subscriptions and Day Pass Bundles (ADR 0009). The hybrid keeps synchronous card confirmation for self-serve while reusing the existing `send_invoice` branch for net-30 orgs, so no new charging primitive is introduced.

## Consequences

- **Far-future bookings take money today**, so the cancellation/refund policy (ADR 0011) ships in the same release — there is no longer a "free hold release."
- **Booking is synchronous**: a card decline fails the booking. `SaveRoomReservation#rollback` MUST destroy the reservation so a declined attempt never leaves a phantom holding the slot.
- **`captured_at` stamps on success only** (the retired `CaptureHold` stamped it even on failure, permanently marking a transiently-failed booking as charged). It is the idempotency marker — `ChargeAtBooking` is a no-op if it's already set.
- **Idempotency keys are required** on every booking-time `PaymentIntent`/charge (reservation id + amount), placed in the Stripe *opts*, plus the local `captured_at` marker, so a retried booking never double-charges.
- **Demo safety**: every money path (`ChargeAtBooking`, `ChargeExtensionDelta`, the $0-no-coverage charge, refunds) is gated on `billing_state == "production"`, identical to the existing `should_charge_*` short-circuit.
- **Net-30 orgs are now invoiced for extensions** (previously slipped through uncharged) — an intended billing correction.
