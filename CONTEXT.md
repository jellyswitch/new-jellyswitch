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

- **A pass is spent by showing up today — "burn on entry."** The burn fires three ways, all the **same act** — "I'm using a pass today" — routed through the **one authority** (`Billing::DayPassBundles::ConsumeOnEntry`): the **door auto-burn** on a successful unlock, a member **"use a pass for today"** in the app, or that same action from the **web account**. Each mints a `DayPass` for *today* and decrements the bundle by one. A bundle pass is burned **only when nothing else already grants access** (membership, a day pass already held for today, a lease, or a reservation take precedence), and **at most once per business-day period** gated by the per-location `day_pass_period_start` rollover (default 04:00), so an evening session crossing midnight is one pass — the check-mint-burn is serialized under the bundle row lock so concurrent triggers can't double-burn. Passes may also be **scheduled** for a future date: scheduling mints a dated `DayPass` now and decrements the bundle immediately (a confirmed reservation), reusing the same burn machinery — so on that day the door opens via the normal access check with no second burn. A member (or an admin on their behalf) can schedule one or many upcoming days, draws come from the **soonest-expiring** bundle, and a still-future scheduled day can be **cancelled** self-serve (the pass is restored). See `docs/adr/0018-day-pass-bundle-scheduling.md`.
- **Redeeming is not entering.** A redemption mints today's `DayPass` — the *right* to be there — but does **not** open a door. At app-only spaces the member still needs the app (or another credential) to unlock, so a **web redeem confirms the pass and hands off to the app**: the web is the action, the app stays the key. See `docs/adr/0017-member-initiated-redemption-is-the-same-burn.md`.
- **Guest pass.** A bundle holder can spend a pass on a **self-attested guest** (name only, no account) from a dedicated "Bring a guest" surface — the host opens the door for them, so the guest needs no app or credential. This is **separate from the `Checkin` model** (a guest never authenticates, so it needs none of Checkin's access/billing machinery). It is the *only* way one account spends more than one pass on the same day — the holder's own auto-burn stays capped at once/day.
- **Redemption ledger.** Every pass leaving a bundle is a logged **Redemption** (`kind: entry | guest | admin_restore | schedule_cancel`): an `entry` redemption (door auto-burn) also mints today's `DayPass`; a `guest` redemption records the guest; an `admin_restore` reverses one; a `schedule_cancel` reverses a cancelled future schedule, restoring the pass. `passes_remaining` is a counter; the ledger is the audit trail for the prepaid value (who, when, why).
- **Admin restore.** An admin can add a burned pass back to a bundle (an `admin_restore` redemption — auditable: who/when/why) for accidental or glitched entries.
- **Expiration defaults to perpetual.** Prepaid passes are stored value; some states (e.g. California, Civil Code §1749.5) prohibit expiration on such instruments, so bundles **never expire by default**. Expiration is an optional per-product (`DayPassType`) setting, measured from purchase, off unless explicitly enabled behind a legal disclaimer, and **hard-blocked for products whose location is in an expiration-restricted state** (a maintainable data list, California included). See `docs/adr/0008-day-pass-bundle-expiration-opt-in-state-restricted.md`.
- **Revenue is recognized at the sale, not the burn.** A Bundle's money is the **purchase** — counted on the day it sells, at the **pack price** (`day_pass_type.amount_in_cents`, the flat N-Pack SKU charge with any volume discount already baked in — never `× quantity`). A subsequent **burn is $0**: it spends already-recognized prepaid value, so it must not add to daily revenue. In operator-facing daily totals ("Who's coming today"), a bundle sale appears as revenue on its purchase day and bundle-sourced entries contribute nothing — mirroring how a new subscription is counted once on creation. See `docs/adr/0009-bundle-revenue-recognized-at-sale.md`.
- **A Bundle buyer is a customer, not a lead.** They've prepaid for multiple visits, so they are **never enrolled in the signup/welcome nurture** (that drip exists to convert non-buyers). Bundles have their **own lifecycle emails** keyed off bundle events, distinct from the single Day Pass's day-anchored emails:
  - **Onboarding** — sent on purchase; explains the mechanics (passes remaining, burn-on-entry, guest pass, expiry-or-never).
  - **Review** ("how are we doing") — sent after the **first burn** (first redemption), because a "how was your visit?" ask only makes sense once they have actually visited — not a fixed number of days after purchase.
  - **Replenishment** — sent when **`passes_remaining` reaches 0** ("you're out — grab another pack"); carries the **membership upsell**, since a buyer who burned through a whole pack is the strongest membership prospect.
- **Replenishment.** The zero-balance nudge above. A Bundle-native lifecycle event (passes exhausted), distinct from the single Day Pass's time-based re-engagement.

_Avoid_: **"credits"** for bundle passes — "Room Credits" is a separate stored-value concept. Say **pass / passes remaining / Bundle / N-Pack**.

## Day Office

A **day-pass kind whose purchase carries a private room for the day**. An office-backed `DayPassType` holds an admin-**ordered room pool** (any of the location's rooms, hidden ones included — a dedicated day office is just a hidden room); buying one — or scheduling a Day Office bundle day — auto-books the **first free pool room** in the admin's priority order as that pass's **office hold**. The buyer never picks the room.

- **The office hold is a normal $0 Reservation** spanning the location's **posted hours** for the purchased date — the pass's money is the SKU price, the hold moves none. It occupies the room in every calendar/availability surface (conflicts with hourly bookings are symmetric — first commitment wins) and gives the holder the room's **Room Lock** for the day, per the ordinary reservation-gated rule.
- **Building access is exactly a normal Day Pass** — approval gate, posted-hours bounds, burn rules, building scoping. The office is *extra*, never a different door privilege.
- **Room availability alone decides sold-out** — a date is buyable iff a pool room is free; the type's `daily_limit` is ignored and hidden for office-backed types (one capacity source). When no office is free, self-serve offers the **regular day pass** (the location's default room-booking type) or another date.
- **Included meeting-room minutes default to 0** — the holder already has a room, so additional call-room time bills straight at the location **Overage** rate. The office hold itself never draws the allowance.
- **Admins may reassign** a hold to any free room (member notified), cancel just the hold (pass keeps its building access), or refund the pass — a refund **cancels the hold and rescinds the pass in one motion**.
- **A Day Office bundle walk-in with no office free still burns and enters** — the door opens on the burned pass, no office is assigned, member and admins are notified, and the pass is admin-restorable. A **guest redemption never allocates an office** — the guest shares the holder's room.

_Avoid_: "office day pass" / "private office pass" — say **Day Office**. And never infer office behavior from a type's *name* (the retired `%office%` name-match) — office-backed is a stored kind.

## Doors & Access

### Building Door

A door that grants **entry to the space itself** — gated on *coverage* (active membership, day pass for today, lease, or staff). Opening one is a **door punch**, the canonical "member physically used the space today" event: it burns Day Pool days, triggers bundle burn-on-entry, and feeds the Quiet lifecycle signal. A Door with **no Room attached** is a Building Door.

### Room Lock

An electric lock protecting **one specific reservable space inside the building** (a meeting room, phone booth, studio). Classified by attachment: a Door **attached to a Room is that Room's lock**. Authorization is about *the resource, not the building* — holding building coverage alone does not open a Room Lock. A Room Lock opens only for:
- **the reservation holder**, during their booking (plus a short early-entry grace when no prior booking occupies the room) — deliberately tighter than the ±60-min building **Access window** (ADR 0013): early building entry is hospitality, early room entry collides with the previous booking;
- **staff**, anytime (setup, cleaning, tours).

An idle reservable room **stays locked** — that is the lock's purpose (a priced room's revenue leaks if coverage alone opens it). V1: holder-only (no invitee/org-mate unlock).
_Avoid_: "exterior/interior door" — that describes the architecture, not the rule. TLH's "Meeting Room **Ext**" lock is architecturally exterior but is a Room Lock. Classify by what the door protects.

### Walk-up space

An interior space with a lock but **no booking requirement** (phone booths). Its door stays **unattached** — coverage-gated like a Building Door, deliberately: requiring a booking for a 5-minute call is hostility, not access control. If the operator later makes the space reservable, attaching its door to the new Room converts it to a Room Lock with no other change.

### Room Entry

The event of opening a **Room Lock**. Logged for audit (who opened which room, when) but **not a door punch**: it never burns Day Pool days, never triggers bundle burn-on-entry, and stays out of building-entry analytics. "Door punch" keeps its exact meaning — *a Building Door open, the member physically entered the space*.
_Avoid_: counting Room Entries in anything that means "visits" or "entries".

### Relationships (doors)

- A **Door** is attached to **at most one Room**; a Room may have multiple Doors (TLH's Meetup Room could have both an interior and an "Ext" lock).
- Attachment is an operator configuration action (on the room/door settings), never inferred from names.
- A **beacon on a door** marks a BLE arrival-unlock **building entrance** — Room Locks are excluded from arrival-unlock, so both room pickers warn and ask for confirmation before attaching a beacon-linked door as a room lock (the TLH front-door lockout, 2026-07-12). Confirm, not block: an operator may legitimately reclassify.
- A **Room Lock** open is a **Room Entry**; a **Building Door** open is a **door punch**.
- **The reservation is the key**: a member reaches a Room Lock only through their booking (reservation card / start notification), never through the general Keys list. Staff reach every door through the admin door list.

## Flagged ambiguities

- "pool" was used loosely for both the day allowance and the meeting-room-minute allowance — resolved: **Day Pool** (distinct days) and **Hour Pool** (free room minutes) are distinct caps with separate fields.
- "Regular" vs "Membership" amenity pricing was opaque (and collided with the bare `price` column) — resolved: **Non-member rate** (`price`) and **Member rate** (`membership_price`). See **Amenity**.
- "credits" is overloaded — **Room Credits** (existing stored value) vs day-pass **Bundle passes** (new). Day-pass packs use **pass / passes remaining**, never "credits".

## CRM / Marketing

### Person
A unified entity representing anyone in the operator's universe: members, past members, day-passers, tour-takers, and prospects. Underneath, every Person is a `User` row. There is **no separate Person model or Person profile screen** — the operator's existing admin member-detail page (`app/views/operator/users/profile.html.erb`, mobile `MemberDetailScreen.js`) serves as the unified Person view. Note: `Operator::UsersController#show` renders `show.html.erb` when `@user == current_user` (member self-view) and `profile.html.erb` otherwise (admin-viewing-member). The CRM timeline lives on `profile.html.erb` — the admin-facing surface.

**Do not say "Contact" or "Lead" in operator-facing UI.** Use "Person" or the lifecycle-stage label.

### Lifecycle Stage
An operator-facing label that summarizes where a Person is in their relationship with the space. Surfaced as a filter on the People list (**web and mobile — parity**) and as a badge on the Person view.

Operator-facing labels:
- **Member** — currently has an active subscription
- **Day-passer** — purchased a day pass within the last 30 days, no active subscription
- **New signup** — signed up but has not purchased, still within the approval window (7 days). Shown in the approval queue.
- **Cold signup** — a New signup that took no action within the approval window (7 days). Drops off the approval queue and is found under the People **"Cold signup"** filter. **Never called a "Lead"** — that term was deliberately dropped as too broad / sales-funnel-y.
- **Past member** — had an active subscription that ended *more than the operator's grace period ago* (configurable per operator, 4–12 months, default 6 months). Members in the grace window still show as **Member**.
- **Quiet** — was active (member or day-passer) but has not had a check-in, door punch, or booking in 30+ days

A **tour** is recorded as an Activity (the `tour` kind), **not** a lifecycle stage — the system tracks that someone toured, but "Tour-taker" is not a class.

**These are not stored as a single enum.** They're derived at query time from subscription state, recent activity, and signup/approval state.

**Stage transitions are automatic, never manually clicked by the operator.** The system derives stage from data: when a Person subscribes they become Member; when their subscription ends + grace expires they become Past member; when they go silent they become Quiet. There is no "Convert Lead" button.

### Interest
Which product(s) a Person is drawn to — **office**, **day pass**, **membership**, or **meeting room**. A Person can hold **several at once** (badges on the Person view, filterable on the People list, web and mobile). Interest is *what* matches a Person to the right campaign or offer — the audience dimension that finally makes **New signups** targetable (no purchase history to derive a stage from). Distinct from **Lifecycle Stage**, which is *where* they are.

A Person's Interest is a set of **tags**, kept deliberately simple — from two sources:
- **Behavioral (the default)** — set automatically, one rule: **their last purchased product** if they've bought anything, otherwise **what they last looked at** (concierge chat intent — already captures `day_pass`/`day_pass_bundle`/`membership` and routes office/meeting-room requests; plan-category browsing; checkout attempts; viewing offices).
- **Staff-set** — a staff member can **add, remove, or adjust** any tag (including overriding a behavioral one) and can **add a Person to a list manually** (even someone not otherwise tagged). Surfaces interest from offline conversations ("called, wants an office").

Interest tags feed the **campaign / list system**: the operator pulls a **list of who to target** for a given interest — e.g. the "viewed day passes *and* membership → credit the day pass toward membership" play — sent in-app or exported.

There is **no separate "waitlist" construct** — the "office waitlist" is simply the People list filtered to the **office** interest tag (offices are usually sold out, so it's the operator's most-used list).

**The office list is a FAIRNESS QUEUE, not a marketing blast.** Ordering: **current customers first** — members and virtual-office (VO) clients — by **earliest account signup** (tenure/loyalty), then **outside parties** in the order they expressed interest. When an office frees up the operator works **down the queue one person at a time** — offers it to the longest-waiting eligible person, waits for a yes/no, then moves to the next — so nobody further down gets an office someone ahead of them still wants. This requires a per-person **outreach status** (not yet contacted / offered / declined / leased), which a "notify the whole list" blast does not. (Other interest lists — day pass, membership — *can* be a bulk send; the office list specifically is one-by-one.)

### Marketing Suppression (culling a list)
Not everyone should stay on a marketing list — "everybody has a story" (moved away, out of work, not a fit). The operator can cull at **two levels**, each with a **reason**:
- **Permanent** — remove from **all** marketing, forever (`marketing_suppressed` + `marketing_suppressed_reason`). For people who've clearly moved on.
- **Per-list / per-campaign** — suppress from **this** list/campaign only, still eligible for others (the campaign's existing `exclude_user!`). For "not this one, maybe later."

Distinct from **unsubscribe** (`email_opted_out`) — that's the *Person's* choice; suppression is the *operator's*.

### Attribution (did the email work?)
The operator must be able to see **which email/campaign caused a conversion** and **how effective each campaign is** — otherwise marketing is guesswork and none of the above earns its keep. Every outreach is measured; nothing sends untracked. Two levels:
- **Per-person** — on the Person's timeline: "bought a day pass / signed up **after** opening the *Winter come-back* email." The Activity table already logs `email_sent` / `email_opened` / `email_clicked`; attribution links a later **conversion** Activity (signup / day_pass / subscription_started / office_lease) back to a recent campaign email the Person opened.
- **Per-campaign** — a scorecard: **sent → opened → clicked → converted** (+ revenue), so a working campaign is distinguishable from a dud. The office fairness-queue is measured too: offered → declined → **leased**.

Attribution is a **window-based, last-touch association** (a conversion within N days of opening a campaign email is credited to it), not a hard causal claim. It closes the loop the whole CRM exists for.

### Point of Contact
A staff User responsible for a given Person — the relationship "owner." Stored as `User.point_of_contact_id`. Defaults to whichever staff member first interacted with the Person (logged the tour, processed the signup, sent the first manual note). Stays consistent across lifecycle stage changes — a New signup's PoC remains their PoC after they become a Member. Reassignable by `admin` or `general_manager` roles only.

PoC is surfaced on the Person view as "Owned by {name}" and is filterable on the People list ("Show only people I own").

### Activity
A timestamped event in a Person's history. Stored as one row in the `activities` table — a single source of truth for the per-person timeline. Activities are immutable history.

**Schema invariants:**
- Every Activity belongs to a User and an Operator (multi-tenant scoping).
- Every Activity has a `kind` (enum of 14 values; see below) and an `occurred_at` timestamp.
- Every Activity carries denormalized `payload` JSONB so the timeline renders without N+1 joins. The one deliberate exception: the room hours booked against a day pass or bundle accrue *after* the row is written, so they can't be denormalized — `TimelineHoursIndex` resolves those at read time for a whole page at once. Anything knowable at write time still belongs in the payload, and a subject that can change after the fact (see `Reservation#sync_activity_payload`) writes back rather than being read live.
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

The visitor-facing thing is always "the Concierge"; what *answers* behind it is a **swappable brain**:
- **Scripted recommender** (current) — a guided, button-driven needs flow (no AI) that recommends a product and captures the Person. **Visitor questions route to the operator's existing Feedback/Messages channel** (there is no separate Concierge inbox — the live-staff inbox and its 5-minute valve were removed 2026-06-18); the staff reply reaches an app-less visitor **by email**.
- **AI concierge** — *deferred to V2*; an LLM brain that answers free-form questions, grounded in real data + the operator's docs, behind a budget cap and degrading to capture on failure. See the V2 notes.

**Need → product (the recommender's job).** The Concierge's core is matching a stated need to a product:
- *Drop-in for a day* → **Day Pass** · *a few days / a week* → **Day Pass Bundle** · *ongoing workspace* → **Membership** — these three are **self-serve**: the Concierge captures the Person, creates the account/lead, and hands off to the existing checkout.
- *Private office for a day* (**Day Office**) · *team meeting* (**Conference Room**) · *long-term private office* (**Office Lease**) — these are **admin-handled**: the Concierge captures the need and pings staff (room bookings aren't automated). Office also routes to a **tour** (must meet before a long-term agreement).

**Conversion lift** is the Concierge's headline metric: of Persons who have a Concierge `chat` Activity, what share go on to a purchase, versus Persons who never chatted — a ratio derived entirely from the **Activity** timeline (no separate analytics pipeline). Anonymous top-of-funnel (web visitors who never became a Person) is **out of scope until V2**.

**Branding is inherited, not re-configured.** The Concierge reads the operator's existing identity (`name`, `primary_color`, `accent_color`, `logo_image`, hours) so every brand is on-brand with zero config. A shared **embed-theme** (the inherited colors + a configurable font + optional accent override) themes **both** the Concierge and the **tour widget** consistently. Per-brand config is deliberately lean (assistant name/avatar, greeting, offer, off-hours message); everything else is inherited or auto-derived from the real catalog.

The persona is **hybrid and honest**: the scripted brain presents as the **branded assistant** (default brand name + logo — never a fake human), and a real staffer's **actual name + avatar** is surfaced only when they join during business hours.

_Avoid_: calling it a "support chat" or "live chat" — it is a **Concierge** whose job is conversion, and the human is only one of its (hours-gated) brains. A captured Concierge visitor is a **Person** (never a resurrected **Lead** — see [[Lifecycle Stage]]).

### Showcase
The operator's embeddable **product-tier widget** for their marketing site: a curated good/better/best presentation of purchasable products (day passes and bundles, memberships) with what's included and live prices from the real catalog (**what's-included = system-derived facts by default — enforced limits shown verbatim, never softened — which the operator's own bullet lines replace entirely when set; regular day passes with their packs form one group, Day Office types with their packs another**), pinned per page to a **product type** and, at a multi-location operator, **always to a location** — an unpinned Showcase at a multi-location operator renders a setup nudge for the embedder, never a guessed or merged catalog (prices live on location pages; the page always knows its place). Single-location operators need no pin. Its call-to-action goes **straight to the existing self-serve checkout** (fewest hops to a transaction — the Concierge bubble on the same page is the questions path, never a checkout middleman) for self-serve products and into capture for admin-handled ones; the **post-purchase screen sets expectations honestly** — product- and approval-aware (at an approval-required operator a buyer is told the team reviews new members before first visit, not "you're in"); a **link-out card** (e.g. a virtual-office service the operator resells, where sign-up happens on the external service's site) is an operator-configured card — label, blurb, price line, outbound URL, **per location** — that renders in a chosen slot: among the membership tiers, among the day passes, or **standalone** (a dedicated page, e.g. /virtual-office, embeds the standalone slot). Clicking a link-out card records the visitor's interest before leaving. All embed widgets share the operator's single **embed-theme** (inherited brand colors + font/accent overrides — one place themes the Concierge, tour widget, Showcase, and Office Inventory together); an inline-rendered widget additionally inherits the host site's own typography by default. A Showcase is **curated, not exhaustive** — the operator chooses which products appear and which tier is featured. **A product's `visible` flag means one thing everywhere: visible in the app ⇒ shown on the website** — there is no separate website-only visibility; hiding a product hides it from both surfaces.

_Avoid_: "catalog widget" (implies an exhaustive listing) and "pricing widget" (ignores the what's-included half). Each dedicated marketing page embeds **the** Showcase pinned to its product type — "the day-pass Showcase", "the membership Showcase" — there are not separate widget products per type.

### Office Inventory
The operator's embeddable **live listing of available offices**. An **Office** is available when it is visible and not covered by an active Office Lease; an office whose current lease is ending may additionally be listed as **coming available** ("Available from <date>", from the lease's end date) — but ONLY via a staff-flipped per-office toggle, never derived automatically from lease dates: a tenant might renew, and their departure is not public information until staff say so. Vacant-now offices always list automatically. Each office carries an operator-set **asking rate** — the advertised monthly price for a vacant office (the lease still owns the real negotiated price; a blank asking rate renders "Contact for pricing"). Visitors click through to an office's details and **inquire**, which records the **office interest tag** — feeding the office waitlist (the People list filtered to that tag) and alerting the location's team.

_Avoid_: "office widget" (collides with the Office model and the office interest tag) and "vacancy list" (operator-internal framing; the visitor-facing frame is what they *can get*, not what the operator failed to fill).

## Reservation (room booking)

A booking of one **Room** for one time window. Pricing is decided **server-side at booking** by `ChargeCalculator`, and the charge is **captured then, not at start** (ADR 0010). A Reservation grants a time-bounded **Access window** around its slot — **not** all-day building access (ADR 0013). A priced (group) **Meeting room** is bookable standalone — no Day Pass required.
_Avoid_: treating a Reservation as a Day Pass. Booking a room neither mints nor requires one. (The retired "comp pass" minted a free Day Pass on paid bookings, and its included minutes mis-priced later edits — see ADR 0012/0013.) The one deliberate reverse arrow: a **Day Office** purchase creates its own $0 office-hold Reservation (ADR 0026) — the pass carries the booking, never a booking minting a pass.

## Call room vs Meeting room

Two kinds of bookable **Room**, distinguished by `hourly_rate_in_cents`:
- **Call room** — a $0 room (`hourly_rate_in_cents == 0`), for an individual taking calls. Covered by a **Day Pass**'s included allowance, then the location **Overage / add-on** rate. Whether a room draws on the day-pass bucket is the per-room **`include_with_day_pass`** flag (defaults to "true when the rate is $0", preserving today's behavior).
- **Meeting room** — a priced room (`rate > 0`), for a **group up to its `capacity`**. Always billed at its own hourly rate, captured at booking; **never** drawn from the day-pass bucket (ADR 0012).

## Access window

The span around a **Reservation** during which the booker may unlock the building on that reservation alone: `Operator.building_access_window_minutes` before start to the same number of minutes after end (default 60). Outside it, the reservation grants no access. Replaces the prior behavior where any reservation granted all-day access (ADR 0013). Day Pass / membership / lease access are unaffected.

## Included-room coverage

Because an included room only grants the access window above, **booking one commits day-pass coverage for its date** — the member decides before booking (ADR 0019). `Billing::Reservations::CoverageState` classifies the situation (`not_applicable` for paid rooms · `already_covered` · `reusable_pass` · `bundle_available` · `needs_purchase`); coverage is committed by organizer steps **before** `ChargeAtBooking` — **reuse** a leftover purchased pass (a cancelled booking's pass, tracked by `day_passes.reservation_id`) → **burn** a bundle pass → **buy** one. `EnforceCoverage` blocks (422) an uncovered included booking (the old silent auto-buy is gone). Meeting-room **overage** is still charged against the covering pass's included minutes, independent of the coverage source, and previewed via `OveragePreview`. On cancel: a bundle pass is restored only if no sibling booking still needs the day; a purchased pass is kept and becomes reusable.
_Avoid_: the retired "silent auto-buy" — a member with a bundle is never charged for a fresh single pass to book an included room.

## Capture-at-booking

Reservation money is **charged at booking and the invoice committed then**, not deferred to a hold-and-settle at start (ADR 0010). Exempt bookers (member / leaseholder / staff) and **demo operators** (`billing_state != "production"`) move no money. Supersedes the retired authorize-hold → capture-on-settle lifecycle (`AuthorizeHold` / `SettleReservationJob` / `CaptureHold`).
_Avoid_: "hold" / "authorize" / "settle" for the new path — those name the retired model.

## Overage / add-on meeting room time

A single **per-location** per-minute rate (operator-facing label: **"Overage / add-on meeting room time"**) charged for **call-room ($0 room) time not covered by a Day Pass allowance** — both a day-passer past their included minutes *and* a booker with no day-pass coverage at all. Lives at the **Location** so it applies even when there is no Day Pass to read a rate from. Distinct from a subscription **plan**'s own overage rate, which is unchanged.

## Cancellation window & refund fee

Operator policy on a **Reservation** cancel (`Operator.cancellation_window_hours`, `Operator.refund_fee_percent`): cancelling **inside** the window (closer to start than the set hours) **forfeits** the charge; **outside** the window **refunds minus the fee %**; a **no-show** (never cancels) → the charge stands (ADR 0011). Binary, not tiered. Member-initiated *reductions* (shorten / end early / switch to a cheaper room) do **not** auto-refund — only a cancel does. An admin may refund or re-price for an operator-forced change (e.g. a room closed for maintenance).

## Login Code

A single-use **6-digit numeric code** emailed to a **User** to log in **without a password** — the member-facing name is **"login code"** (never "OTP", "passcode", or "magic code" in UI). Requesting one emails the code; entering it within **10 minutes** authenticates the user *and*, as a side-effect, marks their email **confirmed** (receiving the code proves inbox control — the same assertion email-confirmation makes). Coexists with password login: it's an additional door to the same account, not a replacement, and it does not disturb the user's password. The login-code email is **transactional**, so it is exempt from the Spam Guard cool-down both directions (ADR 0003) — it always sends and never pauses a drip. See ADR 0016.
_Avoid_: "OTP" / "passcode" / "magic link" in operator- or member-facing copy.
