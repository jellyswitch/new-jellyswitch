# 0019 — Included-room booking commits day-pass coverage

## Status
Accepted (2026-06-30)

## Context
Booking an included room ($0, `include_with_day_pass`) is a commitment to be in
the space that day, but on its own it grants only a ±60-min access window
(ADR 0013). Bundle redemption at booking was opt-in (ADR 0015); when the client
omitted `use_bundle_pass`, the API silently auto-bought a fresh single day pass
for that date — even for a member holding a bundle — wasting their money. There
was no "this will use a pass" notice and no real "buy one?" prompt.

## Decision
An included-room booking must commit day-pass coverage for its date, decided by
the member **before** booking:

- Coverage is classified by `Billing::Reservations::CoverageState`:
  `not_applicable` (paid room) · `already_covered` · `reusable_pass` ·
  `bundle_available` · `needs_purchase`.
- Precedence: **reuse** a leftover purchased pass → **burn** a bundle pass →
  **buy** one. A `reusable_pass` is a purchased pass whose booking was cancelled
  (tracked via `day_passes.reservation_id`), still unused and today-or-future;
  it is re-dated onto the new booking.
- Committed by guarded organizer steps (`ReuseCoveragePass` / `RedeemBundlePass`
  / `BuyCoverageDayPass`) that run **before** `ChargeAtBooking`, which stays
  authoritative for the captured amount.
- `EnforceCoverage` blocks an uncovered included booking (HTTP 422); the silent
  controller auto-buy is deleted.
- **Meeting-room overage** is charged against the covering pass's included
  minutes (bundle / purchased / existing), identical to today's
  `ChargeCalculator#day_pass_overage_cents`, and surfaced pre-book via
  `OveragePreview`.
- On cancel: a **bundle** pass is restored only when no sibling booking still
  needs the day (`other_live_reservation_sharing`); a **purchased** pass is kept
  (no refund) and becomes reusable.

## Consequences
- Capture-at-booking (ADR 0010) and the location overage rate (ADR 0012) are
  unchanged; coverage is committed before the charge is priced.
- Paid rooms (`hourly_rate > 0`) are untouched.
- Members with a bundle no longer double-pay a fresh single pass to book an
  included room.
