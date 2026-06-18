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

## Amenity

A bookable add-on attached to a specific **Room** (e.g. AV equipment, whiteboard, catering). An amenity is selected per **Reservation** and adds to that booking's charge. Each amenity carries **two independent rates**:

- **Non-member rate** (`amenities.price`) — charged to anyone **without** an active membership at the room's location (drop-ins, day-passers, non-members).
- **Member rate** (`amenities.membership_price`) — charged to **active members** at that location.

An amenity is **free** for an audience when that audience's rate is `0`. The two rates are independent, so an amenity may be free for members but paid for non-members (and vice-versa). Which rate a given booking pays is decided **server-side** by `User#should_charge_for_reservation?` and summed in `Reservation#amenity_price` — the charge is computed at booking time, never trusted from the client.

**Behavior is derived from the rate, not a stored type:**

- **Both rates 0** → a passive **room feature** (e.g. whiteboard, monitor). Rendered as an informational chip, never selected, never creates a join row, never charged.
- **Any rate > 0** → an **orderable add-on** (e.g. catering). Selectable per Reservation, creates the `amenities_reservations` join row, and is charged at the booker's applicable rate.

There is no "free but must request" case — every free amenity is a non-selectable feature.

_Avoid_: "Regular price" / "Membership price" in user-facing UI — say **Non-member rate** and **Member rate**. (The DB columns remain `price` / `membership_price`; note that the bare `price` column **is** the non-member rate.)

## Day Pass

A pay-per-day building-access product for non-members. Concretely, a **`DayPass` row is one day of access**, bound to a single calendar `day` — `has_active_day_pass?(day)` grants access when such a row exists for that day. A **`DayPassType`** is the sellable product (name, price, location, optional included meeting-room minutes). A Day Pass is distinct from the **Day Pool** (a *member's* monthly day allowance) — see Membership Usage Limits.

## Day Pass Bundle

A prepaid quantity of day passes a buyer redeems over time (operator-facing: **"5-Pack", "10-Pack",** etc. — collectively a **Bundle**). The pack size is the **`quantity`** on a `DayPassType` (`quantity: 1` is an ordinary single Day Pass; `quantity: N` is an N-Pack priced as a bundle — the volume discount is simply the SKU's price). Buying an N-Pack creates a Bundle holding **N passes**; the operator/member sees **"passes remaining."**

- **A pass is spent by entering — "burn on entry."** Opening the door mints a `DayPass` for *today* and decrements the bundle by one. A bundle pass is burned **only when nothing else already grants access** (membership, a day pass already held for today, a lease, or a reservation take precedence), and **at most once per business-day period** gated by the per-location `day_pass_period_start` rollover (default 04:00), so an evening session crossing midnight is one pass — the check-mint-burn is serialized under the bundle row lock so concurrent door opens can't double-burn. There is **no scheduling** — passes are not assigned to future dates.
- **Guest pass.** A bundle holder can spend a pass on a **self-attested guest** (name only, no account) from a dedicated "Bring a guest" surface — the host opens the door for them, so the guest needs no app or credential. This is **separate from the `Checkin` model** (a guest never authenticates, so it needs none of Checkin's access/billing machinery). It is the *only* way one account spends more than one pass on the same day — the holder's own auto-burn stays capped at once/day.
- **Redemption ledger.** Every pass leaving a bundle is a logged **Redemption** (`kind: entry | guest | admin_restore`): an `entry` redemption (door auto-burn) also mints today's `DayPass`; a `guest` redemption records the guest; an `admin_restore` reverses one. `passes_remaining` is a counter; the ledger is the audit trail for the prepaid value (who, when, why).
- **Admin restore.** An admin can add a burned pass back to a bundle (an `admin_restore` redemption — auditable: who/when/why) for accidental or glitched entries.
- **Expiration defaults to perpetual.** Prepaid passes are stored value; some states (e.g. California, Civil Code §1749.5) prohibit expiration on such instruments, so bundles **never expire by default**. Expiration is an optional per-product (`DayPassType`) setting, measured from purchase, off unless explicitly enabled behind a legal disclaimer, and **hard-blocked for products whose location is in an expiration-restricted state** (a maintainable data list, California included). See `docs/adr/0008-day-pass-bundle-expiration-opt-in-state-restricted.md`.
- **Revenue is recognized at the sale, not the burn.** A Bundle's money is the **purchase** — counted on the day it sells, at the **pack price** (`day_pass_type.amount_in_cents`, the flat N-Pack SKU charge with any volume discount already baked in — never `× quantity`). A subsequent **burn is $0**: it spends already-recognized prepaid value, so it must not add to daily revenue. In operator-facing daily totals ("Who's coming today"), a bundle sale appears as revenue on its purchase day and bundle-sourced entries contribute nothing — mirroring how a new subscription is counted once on creation. See `docs/adr/0009-bundle-revenue-recognized-at-sale.md`.
- **A Bundle buyer is a customer, not a lead.** They've prepaid for multiple visits, so they are **never enrolled in the signup/welcome nurture** (that drip exists to convert non-buyers). Bundles have their **own lifecycle emails** keyed off bundle events, distinct from the single Day Pass's day-anchored emails:
  - **Onboarding** — sent on purchase; explains the mechanics (passes remaining, burn-on-entry, guest pass, expiry-or-never).
  - **Review** ("how are we doing") — sent after the **first burn** (first redemption), because a "how was your visit?" ask only makes sense once they have actually visited — not a fixed number of days after purchase.
  - **Replenishment** — sent when **`passes_remaining` reaches 0** ("you're out — grab another pack"); carries the **membership upsell**, since a buyer who burned through a whole pack is the strongest membership prospect.
- **Replenishment.** The zero-balance nudge above. A Bundle-native lifecycle event (passes exhausted), distinct from the single Day Pass's time-based re-engagement.

_Avoid_: **"credits"** for bundle passes — "Room Credits" is a separate stored-value concept. Say **pass / passes remaining / Bundle / N-Pack**.

## Flagged ambiguities

- "pool" was used loosely for both the day allowance and the meeting-room-minute allowance — resolved: **Day Pool** (distinct days) and **Hour Pool** (free room minutes) are distinct caps with separate fields.
- "Regular" vs "Membership" amenity pricing was opaque (and collided with the bare `price` column) — resolved: **Non-member rate** (`price`) and **Member rate** (`membership_price`). See **Amenity**.
- "credits" is overloaded — **Room Credits** (existing stored value) vs day-pass **Bundle passes** (new). Day-pass packs use **pass / passes remaining**, never "credits".

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

### Concierge
The operator's embeddable, themeable **chat widget** — the conversational front door on their own coworking website. It engages an anonymous visitor, figures out **what they need**, recommends the **right product from the operator's real catalog**, captures them as a **Person**, and routes them onward. It is a *lead-capture + product-recommender + conversion surface*, not a support tool.

The visitor-facing thing is always "the Concierge"; what *answers* behind it is a **swappable brain**, gated by the location's business hours:
- **Live staff** during business hours — a real person replies from the web or mobile admin inbox (with a **5-minute safety valve**: if no staffer replies, the conversation degrades to capture, "someone will get back to you").
- **Scripted recommender** off-hours — a guided, button-driven needs flow (no AI) that recommends a product and captures the Person.
- **AI concierge** — *deferred to V2*; an LLM brain that answers free-form questions, grounded in real data + the operator's docs, behind a per-operator API budget. See the V2 notes.

**Need → product (the recommender's job).** The Concierge's core is matching a stated need to a product:
- *Drop-in for a day* → **Day Pass** · *a few days / a week* → **Day Pass Bundle** · *ongoing workspace* → **Membership** — these three are **self-serve**: the Concierge captures the Person, creates the account/lead, and hands off to the existing checkout.
- *Private office for a day* (**Day Office**) · *team meeting* (**Conference Room**) · *long-term private office* (**Office Lease**) — these are **admin-handled**: the Concierge captures the need and pings staff (room bookings aren't automated). Office also routes to a **tour** (must meet before a long-term agreement).

**Conversion lift** is the Concierge's headline metric: of Persons who have a Concierge `chat` Activity, what share go on to a purchase, versus Persons who never chatted — a ratio derived entirely from the **Activity** timeline (no separate analytics pipeline). Anonymous top-of-funnel (web visitors who never became a Person) is **out of scope until V2**.

**Branding is inherited, not re-configured.** The Concierge reads the operator's existing identity (`name`, `primary_color`, `accent_color`, `logo_image`, hours) so every brand is on-brand with zero config. A shared **embed-theme** (the inherited colors + a configurable font + optional accent override) themes **both** the Concierge and the **tour widget** consistently. Per-brand config is deliberately lean (assistant name/avatar, greeting, offer, off-hours message); everything else is inherited or auto-derived from the real catalog.

The persona is **hybrid and honest**: the scripted brain presents as the **branded assistant** (default brand name + logo — never a fake human), and a real staffer's **actual name + avatar** is surfaced only when they join during business hours.

_Avoid_: calling it a "support chat" or "live chat" — it is a **Concierge** whose job is conversion, and the human is only one of its (hours-gated) brains. A captured Concierge visitor is a **Person** (never a resurrected **Lead** — see [[Lifecycle Stage]]).
