# CRM / Marketing Unification — V1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Unify Jellyswitch's existing-but-fragmented marketing infrastructure (`Campaign`, `ProductEmailTemplate`, `AutomatedWorkflow`, `Lead`) into a coherent CRM surface centered on a per-Person activity timeline, with operator-vocabulary IA, spam-guard invariants, and three new automations covering the full lead → member → past-member → recovery lifecycle.

**Architecture:** Single materialized `activities` table backfilled with 2 years of history. Lifecycle stage derived at query time, never stored. The existing admin member-detail page becomes the unified Person view via a hybrid tabbed timeline (Recent / Emails / Tours / Reservations / Payments / Notes). Three top-level nav items (Leads, Automated Emails, Campaigns) consolidate under a new **People** umbrella. Spam Guard enforces "one active series per Person" and a 30-day cool-down at recipient-resolution time, both as architectural invariants.

**Tech Stack:** Rails 7.x, ActiveJob (Sidekiq-compatible), Sendgrid SMTP + event webhooks, ActionText for template editing, Hotwire/Turbo for partial updates on the Person view. Mobile parity via React Native admin screens rendering Rails views in WKWebView (existing pattern).

**Decisions captured:**
- [CONTEXT.md](../../CONTEXT.md) — domain glossary
- [docs/adr/0001-single-activity-table.md](../../adr/0001-single-activity-table.md)
- [docs/adr/0002-lifecycle-stage-derived.md](../../adr/0002-lifecycle-stage-derived.md)
- [docs/adr/0003-spam-guard-invariant.md](../../adr/0003-spam-guard-invariant.md)

## Platform parity (resolved 2026-05-14)

Per the project's standing iOS / Android / Web parity rule (`memory/feedback_cross_platform_parity.md`):

**Full mobile parity (native screens):**
- Person view tabbed timeline (Phase 2)
- **People list with stage-filter chips (Phase 3.3 + new 3.4)** — native `PeopleListScreen.js` with chip filters + API endpoint
- Point-of-Contact UI on Person view (Phase 4.3) — via WKWebView'd Person view

**Web-only (CRM authoring surfaces — falls under the project's web-only CRM exception):**
- Welcome drip + new automation types (Phase 5)
- Spam Guard cool-down UI + Campaign compose (Phase 6)
- AutomatedWorkflow operator UI (Phase 8.2)
- Per-location grace-days setting (Phase 3.2) — lives inside the web-only Automated Emails screen

**Backend-only (no surface implications):**
- Activity model, logger, source-table callbacks, backfill (Phase 1)
- Lifecycle stage derivation (Phase 3.1)
- PoC schema + default assignment + notifications (Phase 4.1, 4.2, 4.4)
- Sendgrid event webhook (Phase 7)

Nav reorg (Phase 8.1) still touches both surfaces — Rails `_admin_nav.html.erb` and mobile `MoreScreen.js`.

---

## File map

### New files (Rails)
- `app/models/activity.rb` — single source-of-truth events table
- `app/services/activity_logger.rb` — `Activity.log(...)` API
- `app/jobs/backfill_activities_job.rb` — bounded 2-year backfill
- `app/controllers/operator/admin/automated_workflows_controller.rb` — operator UI for `AutomatedWorkflow`
- `app/views/operator/admin/automated_workflows/index.html.erb`
- `app/controllers/sendgrid/events_controller.rb` — webhook receiver
- `app/services/spam_guard.rb` — central enforcement of "one active series + cool-down"
- `app/views/operator/users/_timeline.html.erb` — Recent tab partial
- `app/views/operator/users/_emails_tab.html.erb`
- `app/views/operator/users/_tours_tab.html.erb`
- `app/views/operator/users/_payments_tab.html.erb`
- `app/views/operator/people/index.html.erb` — new People umbrella with stage filter chips
- `db/migrate/[ts]_create_activities.rb`
- `db/migrate/[ts]_add_point_of_contact_to_users.rb`
- `db/migrate/[ts]_add_grace_days_to_locations.rb`
- `db/migrate/[ts]_add_cool_down_to_campaigns.rb`
- `db/seeds/welcome_drip_templates.rb` — brand-stripped Cowork Tahoe seed copy

### New files (Mobile)
- `src/screens/admin/PersonTimelineTabs.js` — Recent/Emails/Tours/etc. tabs for member detail
- `src/components/ActivityTimelineItem.js` — single timeline row renderer
- `src/screens/admin/PeopleListScreen.js` — native People list with stage-filter chips (Phase 3.4)
- `src/components/StageFilterChips.js` — Members · Day-passers · Tour-takers · Past members · Quiet chip row
- `src/components/PersonListItem.js` — photo + name + stage badge + last-activity + PoC row renderer

### Modified files (Rails)
- `app/models/user.rb` — add `lifecycle_stage` derived method, `point_of_contact_id`, `has_many :activities`
- `app/models/lead.rb` — add `Activity.log` callback
- `app/models/campaign.rb` — add `cool_down_days`, integrate Spam Guard into `build_recipient_query`
- `app/models/product_email_template.rb` — add new `email_type` values: `re_engagement`, `past_member_recovery`
- `app/models/automated_workflow.rb` — add new `workflow_type` values: `day_passer_followup`, `room_reservation_followup`, `past_member_recovery`
- `app/models/reservation.rb`, `checkin.rb`, `day_pass.rb`, `subscription.rb`, `door_punch.rb`, `lead_note.rb` — `after_create :log_activity`
- `app/models/invoice.rb` — `after_paid` / `after_failed` Activity hooks
- `app/mailers/application_mailer.rb` — `after_action :log_email_sent`
- `app/jobs/automated_workflows_job.rb` — extend with new workflow types + Spam Guard checks
- `app/controllers/operator/users_controller.rb` — render new Person view tabs
- `app/views/operator/users/show.html.erb` — wire in tabbed timeline
- `app/views/layouts/_admin_nav.html.erb` — People umbrella; remove Leads/Automated Emails/Campaigns from top-level
- `config/routes.rb` — `resources :people` namespace; `post "sendgrid/events"`; `resources :automated_workflows`
- `app/policies/...` — permission checks for People view, campaign-author roles

### Modified files (Mobile)
- `src/screens/admin/MemberDetailScreen.js` — host the timeline tabs
- `src/screens/admin/MoreScreen.js` — update nav to People umbrella
- `src/navigation/AppNavigator.js` — route adjustments

---

## Phase 1: Activity foundation

> **Discipline:** TDD throughout. Each migration/model task has a corresponding test task. Commit after each green test pass.

### 1.1 — Schema

- [x] Write Activity model spec asserting: belongs_to user + operator, validates kind in enum, payload defaults to {}, scoped by occurred_at desc.
- [x] Run spec to confirm it fails (no model yet).
- [x] Generate migration `create_activities` with columns from CONTEXT.md (user_id, operator_id, kind string, subject_id+subject_type, payload jsonb, occurred_at).
- [x] Add indexes: `[user_id, occurred_at]`, `[operator_id, kind, occurred_at]`, `[subject_type, subject_id]`.
- [x] Run migration locally; rerun spec to confirm green.
- [x] **Commit:** "Add Activity model + migration"

### 1.2 — Logger API

- [x] Write spec for `ActivityLogger.log(user:, kind:, subject:, payload:)` — validates kind, denormalizes a few fields from subject if payload is empty, returns the Activity.
- [x] Implement `app/services/activity_logger.rb`.
- [x] Add convenience class method `Activity.log(...)` delegating to ActivityLogger.
- [x] Run specs → green.
- [x] **Commit:** "Add Activity.log API"

### 1.3 — Source-table callbacks

For each model below, write a model spec asserting `after_create` writes one Activity row of the correct kind, then implement the callback.

- [x] `Reservation` → `kind: :reservation`
- [x] `Checkin` → `kind: :checkin`
- [x] `DoorPunch` → `kind: :door_punch`
- [x] `DayPass` → `kind: :day_pass`
- [x] `Subscription` create → `kind: :subscription_started`
- [x] `Subscription` cancel/destroy → `kind: :subscription_ended`
- [x] `Invoice` paid → `kind: :payment_succeeded`
- [x] `Invoice` failed → `kind: :payment_failed`
- [x] `LeadNote` create → `kind: :note`
- [x] `User` after_create → `kind: :signup`
- [x] `ApplicationMailer.after_action :log_email_sent` → `kind: :email_sent` (capture every outbound email)
- [x] **Commit after each model:** keeps PRs reviewable; rollback granularity if any callback breaks production sends.

### 1.4 — Backfill job

- [x] Write spec for `BackfillActivitiesJob.perform(operator_id, since: 2.years.ago)` — for each source model, finds rows in window, writes Activity rows, idempotent on re-run via `Activity.exists?(subject: ...)`.
- [x] Implement job streaming 1k rows at a time (`find_in_batches`).
- [x] Add `Operator.last_activities_backfilled_at` column to track progress.
- [x] Spec idempotency by running twice and asserting no duplicate Activity rows.
- [x] Add rake task `bin/rake activities:backfill_all` that enqueues per-operator.
- [x] **Commit:** "Add 2-year activities backfill job"

---

## Phase 2: Person view — tabbed timeline

### 2.1 — Rails: tabs on existing user show page

- [x] Read [`app/views/operator/users/show.html.erb`](app/views/operator/users/show.html.erb) to understand current structure.
- [x] Add a tab strip at top of show page: Recent · Emails · Tours · Reservations · Payments · Notes.
- [x] Create partial `_timeline_recent.html.erb` rendering `@user.activities.order(occurred_at: :desc).limit(50)` with kind-specific icon + payload-rendered text.
- [x] Create partials `_timeline_emails.html.erb`, `_timeline_tours.html.erb`, `_timeline_reservations.html.erb`, `_timeline_payments.html.erb`, `_timeline_notes.html.erb` — each a filtered subset of activities.
- [x] Use Turbo Frames so tab clicks update inline without full reload.
- [x] Write feature spec asserting the timeline renders activities with correct copy per kind.
- [x] **Commit:** "Add timeline tabs to admin user show page"

### 2.2 — "Log a tour" button

- [x] Add button to user show page header: "Log a tour."
- [x] On click, opens a modal with note field (optional) and "Log" button.
- [x] POST to `users#log_tour` action that calls `Activity.log(user:, kind: :tour, payload: {notes: ..., logged_by_user_id: current_user.id})`.
- [ ] ~~Add People list "Log a tour" entry point that opens a Person picker modal.~~ *Deferred until Phase 3.3/3.4 when the People list lands.*
- [x] Spec: clicking button + submitting modal creates an Activity row of kind `tour`.
- [x] **Commit:** "Add Log a Tour button"

### 2.3 — "Add note" button

- [ ] Add "Add note" button to user show page.
- [ ] On submit, creates `LeadNote` (which already triggers Activity.log via 1.3).
- [ ] Spec.
- [ ] **Commit:** "Add Add Note button to person view"

### 2.4 — Mobile: timeline tabs in MemberDetailScreen

- [ ] Build `PersonTimelineTabs.js` mirroring the Rails tab structure.
- [ ] Build `ActivityTimelineItem.js` rendering one timeline row from an activity object.
- [ ] Wire to existing `adminMembersAPI` — add `activities(user_id, tab)` endpoint.
- [ ] Add tabs to `MemberDetailScreen.js` between header and existing content.
- [ ] Test in iOS sim: dark mode renders, all 6 tabs render.
- [ ] Run Maestro to confirm no regression.
- [ ] **Commit:** "Add per-person timeline tabs to mobile MemberDetailScreen"

---

## Phase 3: Lifecycle stage derivation

### 3.1 — Stage query method

- [ ] Write spec for `User#lifecycle_stage` returning one of `:member, :day_passer, :tour_taker, :past_member, :quiet`.
- [ ] Build cases driven by:
  - `:member` if active subscription
  - `:past_member` if subscription ended > location.past_member_grace_days ago
  - `:day_passer` if day pass within last 30 days, no active subscription
  - `:quiet` if was active but no checkin/door_punch/reservation in 30 days
  - `:tour_taker` otherwise (has Lead row OR has tour activity)
- [ ] Add `User.in_stage(stage)` scope using activity + subscription joins (no enum column).
- [ ] Spec edge cases: someone with both an active subscription AND a Lead row = `:member` (subscription wins).
- [ ] **Commit:** "Derive User#lifecycle_stage from data"

### 3.2 — Per-location grace days

- [ ] Migration: `Location.past_member_grace_days` integer, default 180.
- [ ] Add to Location validations: `inclusion: { in: 120..365 }` (4 months to 12 months).
- [ ] Expose in the Automated Emails config UI as a stage-transition setting at the top.
- [ ] **Commit:** "Add per-location past-member grace period setting"

### 3.3 — People list with stage filters (Rails)

- [ ] Build `app/views/operator/people/index.html.erb` with chip filters at top: All · Members · Day-passers · Tour-takers · Past members · Quiet.
- [ ] Each chip queries `User.in_stage(:label)`.
- [ ] Result list shows: photo + name + stage badge + last activity timestamp + point-of-contact name.
- [ ] Pagination at 50 per page.
- [ ] Expose JSON API at `GET /operator/people.json?stage=<stage>&page=<n>` returning the same shape — consumed by mobile in 3.4.
- [ ] **Commit:** "Add People list with lifecycle stage filters"

### 3.4 — People list with stage filters (Mobile native)

Parity counterpart to 3.3, per platform-parity decision (2026-05-14).

- [ ] Build `src/components/StageFilterChips.js` — horizontal scrollable chip row, controlled by a `selectedStage` prop.
- [ ] Build `src/components/PersonListItem.js` — photo + name + stage badge + last-activity timestamp + PoC name (mirrors the Rails partial).
- [ ] Build `src/screens/admin/PeopleListScreen.js` — header with chip row, FlatList of PersonListItem, infinite scroll via the JSON API from 3.3.
- [ ] Wire to `adminMembersAPI` — add `peopleList({stage, page})` calling `/operator/people.json`.
- [ ] Add to `AppNavigator.js` admin stack; replace the existing "Members" entry point in `MoreScreen.js` with "People" → `PeopleListScreen`.
- [ ] Test in iOS sim across all 5 stages + "All"; tapping a person navigates to existing `MemberDetailScreen`.
- [ ] Run Maestro after this lands (per `feedback_run_maestro_after_ui.md`).
- [ ] **Commit:** "Add native People list screen with stage filters"

---

## Phase 4: Point of Contact

### 4.1 — Schema

- [ ] Migration: `User.point_of_contact_id` references users. Indexed.
- [ ] `User belongs_to :point_of_contact, class_name: 'User', optional: true`.
- [ ] `User has_many :owned_people, class_name: 'User', foreign_key: :point_of_contact_id`.
- [ ] **Commit:** "Add point_of_contact to User"

### 4.2 — Default assignment

- [ ] Helper `User#assign_default_point_of_contact!` — picks current_location's GM, falls back to operator's primary admin.
- [ ] Hook into:
  - `User.after_create` (signup path)
  - `Activity.log(kind: :tour)` (on first tour with no PoC)
  - Lead creation
- [ ] Skip if PoC already set (consistency rule).
- [ ] **Commit:** "Auto-assign default point of contact"

### 4.3 — UI

- [ ] Add "Owned by [GM Sarah ▾]" dropdown on Person show page.
- [ ] Permission-gated: only `admin` or `general_manager` can edit (Pundit policy).
- [ ] On change: write Activity row of kind `note` saying "Owner reassigned from X to Y by Z."
- [ ] Add "People I own" filter chip on People list.
- [ ] **Commit:** "Add point-of-contact UI + filter"

### 4.4 — Notifications

- [ ] When a Person owned by user X has a significant event (email_replied, signup, subscription_ended, lifecycle becomes :quiet), notify X.
- [ ] Reuse existing notification infrastructure (whatever the Activity Feed uses).
- [ ] Spec: PoC receives notification on email_replied activity; non-PoC team members do not.
- [ ] **Commit:** "Notify point-of-contact on significant events"

---

## Phase 5: Welcome drip + new automations

> **Surface:** Web-only (CRM authoring exception, per platform-parity decision 2026-05-14). No mobile screens required.

### 5.1 — Extend ProductEmailTemplate

- [ ] Add new `email_type` values: `re_engagement`, `past_member_recovery`.
- [ ] Update `available_merge_tags` to include any new tags needed (e.g., `{{days_since_last_visit}}`, `{{plan_canceled_on}}`).
- [ ] Update `seed_defaults_for` to include defaults for new types.
- [ ] **Commit:** "Add re_engagement + past_member_recovery email types"

### 5.2 — Brand-stripped Cowork Tahoe seed copy

- [ ] Pull Cowork Tahoe's existing onboarding/follow_up template content from production DB (read-only export).
- [ ] Strip brand-specific copy (replace "Cowork Tahoe" → `{{space_name}}`, etc.).
- [ ] Place in `db/seeds/welcome_drip_templates.rb`.
- [ ] On first deploy + on new operator creation, seed defaults from this file.
- [ ] **Commit:** "Seed welcome drip templates from Cowork Tahoe (brand-stripped)"

### 5.3 — Wire welcome drip enqueue

- [ ] In `DayPass.after_create`, if user has no prior subscription, enqueue Welcome Drip (subject to Spam Guard from Phase 6).
- [ ] In `Crm::CreateLead` (event RSVP path), enqueue Welcome Drip (subject to Spam Guard).
- [ ] Spec: enqueueing happens; double-enqueue is a no-op.
- [ ] **Commit:** "Auto-enqueue Welcome Drip from day-pass and event RSVP"

### 5.4 — Three new AutomatedWorkflow types

- [ ] Add `day_passer_followup`, `room_reservation_followup`, `past_member_recovery` to TYPES.
- [ ] Default config:
  - `day_passer_followup`: `{ days_after: 14 }`
  - `room_reservation_followup`: `{ days_after: 14 }`
  - `past_member_recovery`: `{ days_after_grace: 30 }`
- [ ] Implement each in `AutomatedWorkflowsJob` — fire when conditions met, respect Spam Guard.
- [ ] Spec each.
- [ ] **Commit:** "Add 3 new automation types"

---

## Phase 6: Spam Guard

> **Surface:** Service is backend; UI is web-only (CRM authoring exception). No mobile screens required.

### 6.1 — Central service

- [ ] Spec for `SpamGuard.eligible?(user, sender:, cool_down_days:)`:
  - Returns false if user is currently in any active series (`drip` campaign OR multi-step automation enrolled within the last 60 days)
  - Returns false if user received any email from `sender` operator within `cool_down_days`
  - Returns true otherwise
- [ ] Implement `app/services/spam_guard.rb`.
- [ ] Spec edge: transactional emails (mailers called directly, not through Campaign/Automation) bypass the guard automatically (they don't enqueue, so SpamGuard never gets consulted).
- [ ] **Commit:** "Add SpamGuard service"

### 6.2 — Campaign cool-down column + UI

- [ ] Migration: `Campaign.cool_down_days` integer, default 30.
- [ ] Add to campaign form as dropdown: 0 (off) / 30 / 60 / 90 / custom.
- [ ] Update `Campaign#build_recipient_query` to apply `SpamGuard.eligible?` filter.
- [ ] On campaign compose page, show "X recipients · Y excluded by Spam Guard (hover for reason)."
- [ ] Spec: campaign with 100 candidates and 20 of them in active drip → recipient count = 80.
- [ ] **Commit:** "Add cool-down dropdown + Spam Guard filter to Campaign"

### 6.3 — Automation enqueue checks

- [ ] In `AutomatedWorkflowsJob` and the `ProductEmailTemplate` send path, call `SpamGuard.eligible?` before sending.
- [ ] If not eligible, skip + log to send_log with reason.
- [ ] Spec.
- [ ] **Commit:** "Apply Spam Guard to all automation send paths"

---

## Phase 7: Sendgrid event webhook

### 7.1 — Receiver

- [ ] Add route: `POST /sendgrid/events`.
- [ ] Build `Sendgrid::EventsController#receive` that:
  - Verifies signed payload (Sendgrid Event Webhook signature header)
  - Loops over events array
  - Maps each to Activity kind: `open` → `email_opened`, `click` → `email_clicked`, `bounce`/`dropped` → updates `User.email_bounced` flag, `spamreport` → updates `User.email_opted_out`
  - Looks up the original CampaignSend or User from the smtp-id / unique args
  - Writes Activity row + updates CampaignSend.opened/clicked
- [ ] Spec with fixture payloads from Sendgrid docs.
- [ ] Add to `config/routes.rb`.
- [ ] Document the Sendgrid Event Webhook setup steps in [Sendgrid setup runbook](TODO).
- [ ] **Commit:** "Add Sendgrid event webhook receiver"

### 7.2 — Wire opens + clicks into timeline

- [ ] Verify the Person view's Emails tab shows opened/clicked Activity rows correctly.
- [ ] Spec that an `email_opened` activity follows the corresponding `email_sent` activity.
- [ ] **Commit:** "Wire email engagement events into timeline"

---

## Phase 8: Nav reorg + AutomatedWorkflow UI

### 8.1 — People umbrella

- [ ] Update `app/views/layouts/_admin_nav.html.erb` to remove `Leads`, `Automated Emails`, `Campaigns` from top-level paths array.
- [ ] Add new `People` top-level item.
- [ ] Build `Operator::PeopleController#index` rendering the People list (Phase 3.3) with sub-tabs across the top: Members · Leads · Automations · Campaigns · Templates.
- [ ] Each sub-tab routes to existing controllers (don't duplicate logic — just the nav surface changes).
- [ ] Update mobile nav (`MoreScreen.js`) to mirror.
- [ ] Spec navigation: links land on the right pages.
- [ ] **Commit:** "Consolidate Leads + Automations + Campaigns under People"

### 8.2 — AutomatedWorkflow operator UI (web-only)

> Per platform-parity decision 2026-05-14: this UI is web-only. Mobile operators see automations running via the Person timeline but do not toggle/edit them from mobile.


- [ ] New controller `Operator::Admin::AutomatedWorkflowsController` with `index` and `update`.
- [ ] View `index.html.erb` lists each of the 7 types (4 existing + 3 new) with on/off toggle + plain-English description + editable timing fields.
- [ ] Each type renders as a sentence: *"When [signup happens], send [4 emails] over [1, 3, 7, 14] days."* with the bracketed parts editable inline.
- [ ] Wire to `AutomatedWorkflow.seed_defaults_for(operator, location:)` on first load to ensure rows exist.
- [ ] Spec: toggle creates/updates record; editing sequence_days persists.
- [ ] **Commit:** "Add AutomatedWorkflow operator UI"

---

## Phase 9: Polish + ship-readiness

### 9.1 — Backfill operator settings

- [ ] Run `bin/rake activities:backfill_all` against staging — verify reasonable runtime and no errors.
- [ ] Run `Location.past_member_grace_days` defaults backfill (set to 180 for all existing locations).
- [ ] Run `User#assign_default_point_of_contact!` against all existing Users without a PoC.
- [ ] **Commit:** "Production backfill rake tasks"

### 9.2 — Test sweep

- [ ] Full Rspec suite green
- [ ] Full Minitest suite green
- [ ] Full Maestro suite green (run `bash tests/maestro/run_all.sh`)
- [ ] Manually walk the new Person view in the browser at `/operator/users/[id]` for a member with rich activity history.
- [ ] Manually compose a campaign and verify cool-down exclusion shows correctly.

### 9.3 — Document for operators

- [ ] Add a one-page operator guide at `app/views/operator/people/_guide.html.erb` rendered as an info card on first visit:
  - "What's a Person?"
  - "What do the lifecycle stages mean?"
  - "How automations and campaigns differ"
  - "What's the Spam Guard"

### 9.4 — Final commit + PR

- [ ] Squash WIP commits or keep granular per the deploy memory's preference.
- [ ] PR description references CONTEXT.md + the three ADRs.
- [ ] **NOTE:** Per `feedback_deploy.md`, main auto-deploys to Heroku regardless of CI. Confirm full local test pass before merge.

---

## Out of scope (deferred to V1.5+)

- Public website tour-request form (V1.5)
- Action Mailbox + email reply tracking (V1.5)
- Campaign analytics dashboard (V1.5)
- Custom-trigger workflow builder (V2)
- Lead scoring (V2)
- Saved segments (V2)
- A/B testing on campaigns (V2)
- Wider nav cleanup (Spaces / Community / Money consolidation) — separate sprint per Q23

## Estimated effort

3 weeks of focused development for a single engineer. Phases 1–4 are foundational and sequential. Phases 5–8 can partially parallelize once Activity model lands. Phase 9 must be last.
