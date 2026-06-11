# Commitment Length is an auto-renewing minimum term, not a fixed-end contract

## Context

`Plan.commitment_interval` ("Commitment Length") is meant to hold a member to a minimum term — operators offer it (often at a discount) for revenue certainty. The original implementation did the opposite: the only thing it did was set Stripe `cancel_at = start_date + commitment_duration`, i.e. it **auto-cancelled the membership when the term ended**, and it did **nothing** to stop a member from cancelling early. It was also buggy (`commitment_duration` had no `daily` mapping though `daily` is a valid interval → `nil` → crash; `commitment_interval = 0` counts as "present" → cancel-at-start; a dead `weekly` branch). The feature is configured on 7 hidden plans with 0 active subscribers, so a corrective rebuild is zero-risk.

## Decision

Commitment is a **minimum term on an ongoing, auto-renewing subscription**:

- The subscription does **not** auto-end at the term — remove the `cancel_at = term-end` behavior. A committed sub is created like any ongoing sub.
- **Early cancellation is not immediate.** A member's cancel request during a term is **scheduled to take effect at the current term's boundary** (Stripe `cancel_at` = boundary); they keep access and keep paying through the term they committed to. **Admins/managers can override** and cancel immediately (refunds, cause, goodwill).
- At each boundary the commitment **re-arms** into another term of the same length unless the member opted out beforehand.
- A **dedicated commitment-renewal notice** fires a configurable lead time (default 30 days) before each boundary — the member's opt-out window. This is separate from the routine `renewal_reminder_days` (7-day) billing reminder.
- `commitment_interval` is validated as a positive integer; the duration map covers every real `INTERVAL_OPTIONS` value (`daily` added, dead `weekly` removed).

## Consequences

- Auto-renewing members into successive fixed terms is governed by auto-renewal laws (e.g. California ARL): the 30-day notice + clear up-front disclosure + an easy opt-out path are compliance requirements, not just UX niceties.
- "Discount for commitment" is expressed purely through plan pricing (the operator prices the committed plan lower); no separate discount mechanism is introduced.
- The commitment boundary is computed by walking term-length windows from `start_date`, analogous to `monthly_anniversary_window` (see ADR 0004).
