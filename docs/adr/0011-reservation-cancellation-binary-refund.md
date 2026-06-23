# Reservation cancellation is a binary refund policy on one unified pipeline

A **Reservation** cancel is governed by two existing operator settings: `Operator.cancellation_window_hours` and `Operator.refund_fee_percent`. Cancelling **inside** the window (closer to start than the set hours) **forfeits** the charge; cancelling **outside** the window **refunds the charge minus `refund_fee_percent`**; a **no-show** (never cancels) → the charge stands. The policy is **binary** (no tiers). Every cancel path — member API, admin API, and the web/operator action — runs through **one refund pipeline** (`Billing::Invoices::Refunds`), refunding **all** invoices belonging to the reservation under a row lock.

## Context

Under capture-at-booking (ADR 0010) the money is already taken, so a cancel is now a *refund*, not a hold release. The settings and the binary semantics already exist and were enforced for the member path, but as a partial *capture* of a hold. Two further gaps existed: the **web/operator** cancel only set `cancelled = true` (no fee, no release), and the admin cancel refunded only the single Invoice keyed by `reservation.stripe_payment_intent_id` — missing extension-delta invoices (a reservation can carry several PaymentIntents/Invoices). There is no `Invoice → Reservation` foreign key today.

## Decision

- Invert the existing window/fee logic from partial-**capture** to partial/no-**refund**, preserving the exact thresholds and outcomes.
- Add a nullable `invoices.reservation_id`, stamped at booking and on every extension, so a cancel can refund **all** of a reservation's invoices. `Reservation has_many :invoices`.
- Route member, admin, and web cancels through one `CancelReservation → Refunds` pipeline, under `with_lock` + `unscoped` reload (preserving the cancel-vs-capture race protection the member path already had).
- Member-initiated **reductions** (shorten / end early / switch to a cheaper room) do **not** auto-refund — refunds happen only via a real cancel. An **admin** may refund/re-price for an operator-forced change.
- Tiered refunds are explicitly deferred until an operator needs them.

## Why binary

"Cancel within X hours and you pay in full" is exactly a deposition/legal-style cancellation policy — the operator's actual need (last-minute cancels are common and costly). It's already coded and configured per-operator; tiers add operator-config surface and member confusion for a case the window threshold already handles.

## Consequences

- **New nullable `invoices.reservation_id`** (added concurrently); refund-all is unsafe until it is stamped at booking and on extensions.
- The **fee math** lives in the refundable adapter, selected by a mode (member/admin/forced); `RefundableFactory` returns a `NotRefundable` null-object for already-refunded/void invoices (see ADR 0014) so the multi-invoice loop never crashes.
- **Refund inversion risk**: inside-window = refund $0, outside = refund minus fee — the opposite mechanism to the old hold logic; tests pin both directions.
- **Demo operators** issue no real refund (gated like every money path).
- **No-show is unchanged in spirit** — the charge stands; "no-show costs no day" (ADR 0004) governs Day Pool access only, never the room charge.
