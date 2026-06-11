# Jellyswitch — Domain Glossary

This file is a glossary, not a spec. It defines the canonical vocabulary used in the Jellyswitch codebase. When you encounter a term used inconsistently in code or conversation, this file is the source of truth.

For architectural decisions (the *why* behind the vocabulary), see `docs/adr/`.

---

## Commitment

A **minimum term** a member agrees to when subscribing to a plan, set by `Plan.commitment_interval` (a count of the plan's billing intervals — e.g. `6` on a monthly plan = 6 months). Operator-facing label: **"Commitment Length."** The member cannot freely cancel before the term ends; the operator's incentive to offer it is usually a discounted price for committing.

A Commitment is a **floor on an ongoing subscription, not a one-off fixed-length contract** — the subscription does **not** end when the term is reached. Instead the commitment **re-arms for another term of the same length** unless the member opts out before the boundary (prompted by an expiry notification). Cancellation during a term always takes effect at the **current term's boundary**, never mid-term (admins can override and cancel immediately).
_Avoid_: "contract" / "lease" (a **Lease** is a distinct office-tenancy concept) and "fixed term" (a Commitment auto-renews into successive terms, it doesn't end after one).

## Membership Usage Limits

A plan can cap how much a member consumes per period. There are two independent caps, each backed by its own monthly "pool":

### Day Pool
The number of **distinct days a member may physically use the space** within a period, set by `Plan.day_limit` (gated by `Plan.has_day_limit`). Operator-facing label: **"Monthly Limit"** ("Limit number of days per month to:"). A *day is used* when the member **opens the door** (a door punch) **at the plan's location** on that calendar day — multiple entries on one day still count as one day. Check-ins and reservations do **not** burn a Day Pool day; a no-show (booked but never entered) costs no day. Enforced at building-access / door-open time, not at booking time. Location-scoped: an entry at one location does not draw from a plan tied to another location.
_Avoid_: "visit limit", "day cap" — say **Day Pool** for the allowance and **Monthly Limit** for the operator-facing setting.

### Day Credit
A manual, admin-granted adjustment that returns one (or more) used days to a member for the current period — for door malfunctions, goodwill, etc. Increases the member's remaining Day Pool. Auditable (who granted it, when, why).

### Hour Pool
The number of free **meeting-room minutes** a member gets per period, set by `Plan.included_meeting_room_minutes`, with `Plan.overage_rate_in_cents` charged beyond it. Only **free/standard** rooms (not premium/paid rooms) draw from this pool, and only at the plan's own location.
_Avoid_: "minute pool", "room credits" — say **Hour Pool**.

### Billing Period
The monthly window a pool is measured against. For Stripe-billed subscriptions it is the Stripe `current_period_start..current_period_end`; for comp/manual subscriptions it is the `start_date` day-of-month anniversary window (`Subscription#monthly_anniversary_window`).

## Relationships

- A **Plan** may define a **Day Pool** and/or an **Hour Pool**; both are measured per **Billing Period**.
- A **Reservation** draws from the **Hour Pool** of the **Billing Period it falls in** — booking for next month draws from next month's Hour Pool, not the current one. The charge is *date-aware*, evaluated against the reservation's date, not "now".
- A **door punch** draws from the **Day Pool** of the **Billing Period the entry falls in**.
- Exhausting the **Day Pool** revokes a member's *building access* only — it does **not** revoke membership identity (they remain a Member, still billed, still rendered as active). The day-limit gate lives on the building-access path, never inside `has_active_subscription?`.
- A **Day Credit** offsets door-punch days within a period, raising the member's remaining Day Pool.

## Flagged ambiguities

- "pool" was used loosely for both the day allowance and the meeting-room-minute allowance — resolved: **Day Pool** (distinct days) and **Hour Pool** (free room minutes) are distinct caps with separate fields.

## CRM / Marketing

### Person
A unified entity representing anyone in the operator's universe: members, past members, day-passers, tour-takers, and prospects. Underneath, every Person is a `User` row. There is **no separate Person model or Person profile screen** — the operator's existing admin member-detail page (`app/views/operator/users/profile.html.erb`, mobile `MemberDetailScreen.js`) serves as the unified Person view. Note: `Operator::UsersController#show` renders `show.html.erb` when `@user == current_user` (member self-view) and `profile.html.erb` otherwise (admin-viewing-member). The CRM timeline lives on `profile.html.erb` — the admin-facing surface.

**Do not say "Contact" or "Lead" in operator-facing UI.** Use "Person" or the lifecycle-stage label.

### Lifecycle Stage
An operator-facing label that summarizes where a Person is in their relationship with the space. Surfaced as a filter on the People list and as a badge on the Person view.

Operator-facing labels:
- **Member** — currently has an active subscription
- **Day-passer** — purchased a day pass within the last 30 days, no active subscription
- **Tour-taker** — explicitly expressed interest (tour form, event RSVP, walk-in tour logged) but has not purchased
- **Past member** — had an active subscription that ended *more than the operator's grace period ago* (configurable per operator, 4–12 months, default 6 months). Members in the grace window still show as **Member**.
- **Quiet** — was active (member or day-passer) but has not had a check-in, door punch, or booking in 30+ days

**These are not stored as a single enum.** They're derived at query time from subscription state, recent activity, and explicit Lead annotations. The "Lead" model in code is a sales annotation on a User; it does not represent a distinct person.

**Stage transitions are automatic, never manually clicked by the operator.** The system derives stage from data: when a Person subscribes they become Member; when their subscription ends + grace expires they become Past member; when they go silent they become Quiet. There is no "Convert Lead" button.

### Point of Contact
A staff User responsible for a given Person — the relationship "owner." Stored as `User.point_of_contact_id`. Defaults to whichever staff member first interacted with the Person (logged the tour, processed the signup, sent the first manual note). Stays consistent across lifecycle stage changes — a Tour-taker's PoC remains their PoC after they become a Member. Reassignable by `admin` or `general_manager` roles only.

PoC is surfaced on the Person view as "Owned by {name}" and is filterable on the People list ("Show only people I own").

### Activity
A timestamped event in a Person's history. Stored as one row in the `activities` table — a single source of truth for the per-person timeline. Activities are immutable history.

**Schema invariants:**
- Every Activity belongs to a User and an Operator (multi-tenant scoping).
- Every Activity has a `kind` (enum of 14 values; see below) and an `occurred_at` timestamp.
- Every Activity carries denormalized `payload` JSONB so the timeline renders without N+1 joins.
- Every Activity also carries a polymorphic `subject` foreign key back to the source record (CampaignSend, Reservation, etc.) so operators can drill in for full detail.
- Activity rows are written at the moment the event happens, via `Activity.log(user:, kind:, subject:, payload:)`.

**The 15 kinds (Day 1):**
`signup`, `tour`, `checkin`, `door_punch`, `reservation`, `day_pass`, `subscription_started`, `subscription_ended`, `payment_succeeded`, `payment_failed`, `note`, `email_sent`, `email_opened`, `email_clicked`, `email_replied`.

`door_punch` is kept distinct from `checkin` because they signal different things: a check-in is the member explicitly indicating "I'm here today"; a door punch is physical building access. Both count toward the Quiet threshold; both render in the timeline with different copy.

**Critical rule:** `email_sent` captures **every** outbound email — campaign, automation, AND transactional (receipts, password resets, booking confirmations). The operator cares about total volume, not just marketing volume.

**Backfill:** Existing reservations, check-ins, day-passes, subscriptions, invoices, campaign sends, and lead notes are backfilled into the activity table on deploy. Backfill window is bounded to **the last 2 years** (2024-05-14 → ship date) — older data is left in source tables only, retrievable on demand if needed. Backfill runs as a batched background job, scoped per-operator, idempotent against a `last_backfilled_at` timestamp, streamed in 1k-row chunks. Email-engagement events (opened/clicked/replied) cannot be backfilled and start counting from ship-day. Transactional `email_sent` events cannot be backfilled before the `CampaignSend` model existed (April 2026); only campaign emails have history.

**Deferred kinds** (not in Day 1): `email_bounced`, `subscription_renewed` (derived from `payment_succeeded`), `payment_refunded`, `lifecycle_stage_changed` (derived), `call_logged`, `meeting_logged`.

Activities are what drive the **per-person timeline** — the central "I get it" surface of the CRM. Every email a Person receives, every interaction the operator has with them, every transaction, appears in this single feed on the Person view.

### Mention vs Customer Tag
Both use the same `@` autocomplete in the **team Feed** (posts and comments), but the effect depends on who is tagged:
- **Mention** — tagging a **staff** teammate. Sends them a "X mentioned you" push notification (it's directed *at* them).
- **Customer Tag** — tagging a **member/customer**. Mirrors the note onto that customer's client record (their notes/timeline) and is **silent to the customer** — no push. It's an internal note *about* them, never a message *to* them.

A customer must never receive a push for an internal note that merely discusses them.

### Campaign
A single email or a series of emails sent to a defined audience. Two types:
- **Single** — one email to one audience, fires once when activated
- **Series** (called `drip` in code) — multiple emails over time with delay between each

Campaigns are operator-authored and operator-triggered. Each campaign exposes a **cool-down window** (also called suppression window) that excludes anyone who has received another email from this operator within the last N days. Default is 30 days, configurable per-campaign (operator can pick 0/30/60/90 or custom). This prevents spamming people who are already in another active series.

Use case: "Send a winter come-back email to all day-passers from last summer who haven't returned in 60 days, but skip anyone who got an email from us in the last 30 days."

**Operator-facing wording:** "Send an email" (single), "Run a series" (drip).

### Automation
A trigger-based rule that sends emails when a condition is met, without operator intervention.

**Two underlying systems in code today, both surfaced together under the unified "Automated Emails" sub-tab:**
- **`ProductEmailTemplate`** (already has full UI at `/operator/product_email_templates`) — fires on product purchase events. Three current `email_type` flavors: `onboarding` (immediately after purchase), `follow_up` (after configurable delay), `nudge` (signup-without-purchase prompt).
- **`AutomatedWorkflow`** (no UI yet, runs nightly via `AutomatedWorkflowsJob`) — fires on time-based logic. Four current `workflow_type` values: `signup_nurture`, `re_engagement`, `past_due_followup`, `booking_reminder`.

**New automation types to add in V1:**
- `day_passer_followup` — N days after a day pass with no return visit, encourage repeat or convert to membership
- `room_reservation_followup` — N days after a conference-room reservation, encourage repeat or convert
- `past_member_recovery` — fires when subscription ended + per-location grace period (default 180 days) has expired

These extend the `ProductEmailTemplate` model (adding new `email_type` values like `re_engagement` for product types `day_pass`, `reservation`, `membership`) so they appear in the existing UI alongside Onboarding / Follow-Up / Nudge.

**Campaigns vs Automations:** Operator manually decides who and when for Campaigns. Automations decide themselves based on rules.

### Past-Member Grace Period
A per-location setting (default 180 days, range 4–12 months) that controls when a Person whose subscription has ended transitions from `Member` lifecycle stage to `Past member`. Lives in the operator's Automated Emails configuration screen because it's effectively the trigger condition for the `past_member_recovery` automation. Stored as `Location.past_member_grace_days`.

### Email composition surfaces
Two distinct sections in the operator UI, both housed under the **People** top-level tab:
1. **Automated Emails** — toggle, edit, and configure trigger-based emails (existing `ProductEmailTemplate` UI plus new types).
2. **Campaigns** — author and send manual one-time blasts and series with configurable cool-down windows.

### Spam Guard (system-wide invariant)
A Person can be enrolled in **at most one active series at a time** — campaign OR automation, not both. If a Person is already receiving the Welcome Drip, they are excluded from being enrolled in any campaign or other automation series until the Welcome Drip completes (or they're manually un-enrolled).

In addition, a per-campaign **cool-down window** (default 30 days, configurable per-campaign in the dropdown: 0/30/60/90/custom) excludes anyone who has received any email from this operator within the last N days.

These two rules together mean: a single recipient receives at most one operator-driven email every N days, and is never enrolled in two simultaneous series. This is enforced at recipient-resolution time in `Campaign#build_recipient_query` and at enqueue time in the automation logic. The "I'm very sensitive to not being spammy" principle is a non-negotiable design constraint, not a configurable setting.

### Operator nav (V1 reorg)
The CRM build introduces a new top-level **People** umbrella that absorbs three existing top-level items (Leads, Automated Emails, Campaigns) and renames "Members & Groups" → "People." Net top-level item count: 16 → 13. A wider nav cleanup (consolidating Spaces, Community, Money) is **deferred to a separate sprint** to keep the CRM PR reviewable.

People sub-tabs: Members · Leads · Automations · Campaigns · Templates.
