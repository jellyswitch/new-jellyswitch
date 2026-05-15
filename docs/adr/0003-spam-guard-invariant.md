# Spam Guard: one active drip per Person + universal cool-down

A Person can be enrolled in **at most one active series at a time** (campaign OR automation, never both simultaneously), and any campaign send respects a **cool-down window** (default 30 days, configurable per campaign) excluding anyone who has received any operator-driven email within that window. Both rules are enforced at recipient-resolution time and at automation enqueue time. They are non-negotiable architectural invariants, not configurable settings.

## Considered Options

- **Spam Guard as architectural invariant (chosen).** Recipient-query and enqueue-check both enforce the rules. Operators *can* configure the cool-down window per campaign (0/30/60/90/custom) but cannot disable the one-active-series rule.
- **Per-campaign suppression only.** Each campaign has its own suppression window. Members can still be in two series at once. Easier to implement; meaningfully more spammy in practice.
- **No automated guard, operator discretion.** Trust operators to know what they're sending. Simplest code; worst outcomes when an operator doesn't realize a person is already in another series.

## Why an invariant, not a setting

The product owner's stated principle is *"I'm very sensitive to not being spammy."* Settings degrade over time as new operators join who don't share that sensitivity. Architecture preserves it. By making the guard impossible to disable, every operator on the platform — present and future — inherits the standard.

## How it's enforced

- **`Campaign#build_recipient_query`** filters out users currently enrolled in any other active series and users who received any email from this operator within `cool_down_days`.
- **Automation enqueue logic** (the nightly `AutomatedWorkflowsJob` and the post-purchase callbacks for `ProductEmailTemplate`) checks the same conditions before enrolling a Person in a new automation.
- **"Active series enrollment"** is queried at runtime, not stored as a column on User: a user is currently enrolled if they have a `CampaignSend` row from a `drip`-type Campaign or an in-progress automation step within the last `series_max_duration` days.

## Consequences

- **Some "missed" sends.** A Person who would have been a great recipient for a seasonal campaign is excluded because they're in the Welcome Drip. Acceptable trade-off — they're already getting attention.
- **Operators may be confused** the first time their campaign shows "47 recipients excluded by cool-down." The Campaign compose UI must surface this count and the reason transparently.
- **Cool-down is a new column** (`Campaign.cool_down_days`, default 30) — not the existing `suppression_window_days` (default 7) which has a different meaning ("don't send the same campaign to the same person twice within N days"). Both columns coexist; the new cool-down is operator-facing, the existing suppression is per-campaign deduplication.
- **A future "transactional bypass" is intentionally not added.** Password resets, payment receipts, and booking confirmations skip the Spam Guard automatically because they're sent from `ApplicationMailer` directly without going through Campaign or Automation enrollment.
