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

- [x] Add "Add note" button to user show page.
- [x] On submit, creates `LeadNote` (which already triggers Activity.log via 1.3). Auto-creates a Lead for the User if none exists in the current tenant.
- [x] Spec.
- [x] **Commit:** "Add Add Note button to person view"

  *Side effect (bundled in this commit):* `Lead.belongs_to :ahoy_visit` relaxed to `optional: true` — admin-created leads from this surface have no web visit. CONTEXT.md already frames Lead as "a sales annotation on a User," consistent with this.

### 2.4 — Mobile: timeline tabs in MemberDetailScreen

- [x] Build `PersonTimelineTabs.js` mirroring the Rails tab structure.
- [x] Build `ActivityTimelineItem.js` rendering one timeline row from an activity object.
- [x] Wire to existing `adminMembersAPI` — add `activities(user_id, tab)` endpoint (Rails `Api::V1::Admin::MembersController#activities` + `GET /api/v1/admin/members/:id/activities?tab=…`).
- [x] Add tabs to `MemberDetailScreen.js` between header and existing content.
- [ ] Test in iOS sim: dark mode renders, all 6 tabs render. *Deferred: needs Rails staging deploy or local Rails server pointing the app at it (the dev base URL is `https://jellyswitch-staging.herokuapp.com/api/v1` and staging doesn't yet have the new endpoint).*
- [x] Run Maestro to confirm no regression — 8/8 PASS against the previously-installed bundle. *Note: Maestro ran against the installed app, not against a rebuilt bundle including these new components. Components syntax-check clean but a full re-validation needs a rebuild.*
- [x] **Commit:** "Add per-person timeline tabs to mobile MemberDetailScreen" (mobile commit `9ea90d3` + Rails commit `c9dcc12e`)

  *Bundled in this phase, separate commits:*
  - Rails-side merge + cleanup: `46a26fa6` ("Merge main into feature/mobile-api") + `feb25f4c` ("Post-merge cleanup: sync schema.rb + fix 5 stale specs"). 957 RSpec examples / 0 failures post-merge.
  - Mobile-side theme system landed first: `a3fecf5` ("Add persisted Auto/Light/Dark theme system across the app") — pre-existing WIP that was never committed; now in. Phase 2.4 components use `useTheme()` and flip with the active palette.

---

## Phase 3: Lifecycle stage derivation

### 3.1 — Stage query method

- [x] Write spec for `User#lifecycle_stage` returning one of `:member, :day_passer, :tour_taker, :past_member, :quiet`.
- [x] Build cases driven by:
  - `:member` if active subscription
  - `:past_member` if subscription ended > location.past_member_grace_days ago
  - `:day_passer` if day pass within last 30 days, no active subscription
  - `:quiet` if was active but no checkin/door_punch/reservation in 30 days
  - `:tour_taker` otherwise (has Lead row OR has tour activity)
- [x] Add `User.in_stage(stage)` scope using activity + subscription joins (no enum column).
- [x] Spec edge cases: someone with both an active subscription AND a Lead row = `:member` (subscription wins).
- [x] **Commit:** "Derive User#lifecycle_stage from data"

  *Implementation note:* Per ADR-0002, no `lifecycle_stage` column added. Grace days is currently `User::DEFAULT_PAST_MEMBER_GRACE_DAYS = 180`; Phase 3.2 will swap to per-location lookup. CONTEXT.md's "members in grace still show as Member" honored — the in-grace check sits inside the `:member` branch. `:day_passer` takes precedence over `:past_member` (a returning past member who buys a day pass shows as `:day_passer`).

### 3.2 — Per-location grace days

- [x] Migration: `Location.past_member_grace_days` integer, default 180.
- [x] Add to Location validations: `inclusion: { in: 120..365 }` (4 months to 12 months).
- [x] Expose in the Automated Emails config UI as a stage-transition setting at the top.
- [x] **Commit:** "Add per-location past-member grace period setting"

  *Implementation notes:*
  - `User#lifecycle_stage` instance method now reads `current_location&.past_member_grace_days || DEFAULT_PAST_MEMBER_GRACE_DAYS` via a private `past_member_grace_days_threshold` helper.
  - `User.in_stage(stage)` scope honors per-location grace via a LEFT JOIN to `locations` and a `COALESCE(locations.past_member_grace_days, 180)` cutoff in SQL — no longer uses the global constant for the boundary check.
  - UI lives on `app/views/operator/product_email_templates/index.html.erb`. Form posts to `PATCH /locations/:location_id/past_member_grace_days` (new `update_past_member_grace_days` action on `Operator::LocationsController`) which authorizes via `LocationPolicy#update?` and redirects back to `product_email_templates_path`.

### 3.3 — People list with stage filters (Rails)

- [x] Build `app/views/operator/people/index.html.erb` with chip filters at top: All · Members · Day-passers · Tour-takers · Past members · Quiet.
- [x] Each chip queries `User.in_stage(:label)`.
- [x] Result list shows: photo + name + stage badge + last activity timestamp + point-of-contact name.
- [x] Pagination at 50 per page.
- [x] Expose JSON API at `GET /operator/people.json?stage=<stage>&page=<n>` returning the same shape — consumed by mobile in 3.4.
- [x] **Commit:** "Add People list with lifecycle stage filters"

  *Implementation notes:*
  - Route: `resources :people, controller: "operator/people", only: [:index]` → `GET /people`. Helper: `people_path(stage: …)`.
  - Filter via `?stage=member|day_passer|tour_taker|past_member|quiet` query param. Unknown values fall back to `all`. Default sort: by name. Pagination 50/page via Pagy (matches existing operator list pattern).
  - `point_of_contact_name` is rendered as `null` in JSON and omitted from the HTML for Phase 3.3. Phase 4.3 will wire it up (column doesn't exist yet — Phase 4.1 schema migration).
  - Stage badges + labels are constants on `Operator::PeopleController` (`STAGE_LABELS`, `STAGE_BADGE_CLASSES`); `PeopleHelper#stage_badge` renders the Bootstrap pill.
  - Pundit `PersonPolicy#index?` allows admin/community_manager/general_manager/superadmin.
  - **No nav entry yet** — Phase 8.1 wires the People umbrella into `_admin_nav.html.erb`. Currently reachable only by visiting `/people` directly.

### 3.4 — People list with stage filters (Mobile native)

Parity counterpart to 3.3, per platform-parity decision (2026-05-14).

- [x] Build `src/components/StageFilterChips.js` — horizontal scrollable chip row, controlled by a `selectedStage` prop.
- [x] Build `src/components/PersonListItem.js` — photo + name + stage badge + last-activity timestamp + PoC name (mirrors the Rails partial).
- [x] Build `src/screens/admin/PeopleListScreen.js` — header with chip row, FlatList of PersonListItem, infinite scroll via the JSON API from 3.3.
- [x] Wire to `adminMembersAPI` — add `peopleList({stage, page})` calling `/admin/people` (resolves to `/api/v1/admin/people` via base URL).
- [x] Add to `AppNavigator.js` admin stack; new "PEOPLE" section at top of `MoreScreen.js` menu with "People" → `PeopleListScreen`. (Existing Members bottom tab left untouched — Phase 8.1 will reorg.)
- [ ] Test in iOS sim across all 5 stages + "All"; tapping a person navigates to existing `MemberDetailScreen`. *Blocked: requires the sibling API endpoint (see follow-on below) deployed to staging and an app rebuild.*
- [ ] Run Maestro after this lands. *Same blocker — the new screen has no exercise path until the API endpoint exists.*
- [x] **Commit:** mobile commit `33694b3` "Add native People list screen with stage filters"

  **Follow-on Rails work needed before mobile can consume:**
  - Add `GET /api/v1/admin/people` endpoint on `feature/mobile-api` (or wherever the v1 API namespace lives). Reuse the JSON shape from `Operator::PeopleController#people_json`. The mobile app's `peopleList({stage, page})` already points at `/admin/people`.

  *Notes:*
  - Plan said "replace existing Members entry in MoreScreen" — MoreScreen has no Members entry (Members is a bottom tab). Added a new PEOPLE section at the top instead.
  - testID conventions: `people-chip-{stage}`, `person-list-item-{id}`, `people-list`.
  - Each chip switch resets pagination to page 1; pull-to-refresh + infinite scroll via FlatList.

---

## Phase 4: Point of Contact

### 4.1 — Schema

- [x] Migration: `User.point_of_contact_id` references users. Indexed.
- [x] `User belongs_to :point_of_contact, class_name: 'User', optional: true`.
- [x] `User has_many :owned_people, class_name: 'User', foreign_key: :point_of_contact_id`.
- [x] **Commit:** "Add point_of_contact to User"

  *Notes:*
  - Self-referential FK via `add_reference :users, :point_of_contact, foreign_key: { to_table: :users }`.
  - `dependent: :nullify` on `owned_people` — if a staff member is deleted, their owned Persons stay but lose their owner. (Beats `restrict` which would block deletion, and `destroy` which would cascade-delete real members.)
  - PoC display in JSON and HTML still returns `nil` until Phase 4.3 wires it up. Phase 4.2 will auto-assign on signup/tour/lead-create.

### 4.2 — Default assignment

- [x] Helper `User#assign_default_point_of_contact!` — picks current_location's GM, falls back to operator's primary admin.
- [x] Hook into:
  - `User.after_create` (signup path)
  - `Activity.log(kind: :tour)` (on first tour with no PoC)
  - Lead creation
- [x] Skip if PoC already set (consistency rule).
- [x] **Commit:** "Auto-assign default point of contact"

  *Notes:*
  - Uses `update_column(:point_of_contact_id, ...)` to skip validations and callbacks (avoids re-firing User's own after_create chain on a stale record).
  - Staff users (admin/general-manager/community-manager/superadmin per `User::STAFF_ROLES`) skip the assignment — a GM doesn't get themselves as a PoC.
  - Candidate priority: GM at `current_location` (oldest by `created_at`) → fall back to operator's oldest admin. Returns nil if neither exists; assignment is a silent no-op in that case.
  - Hooks: `User.after_create` (right after `log_signup_activity`), `Activity.after_create` (when kind == "tour"), `Lead.after_create`.

### 4.3 — UI

- [x] Add "Owned by [GM Sarah ▾]" dropdown on Person show page.
- [x] Permission-gated: only `admin` or `general_manager` can edit (Pundit policy).
- [x] On change: write Activity row of kind `note` saying "Owner reassigned from X to Y by Z."
- [x] Add "People I own" filter chip on People list.
- [x] **Commit:** "Add point-of-contact UI + filter"

  *Notes:*
  - Web dropdown auto-submits on change via `onchange="this.form.requestSubmit()"` (existing codebase pattern, no Stimulus controller needed). Route: `PATCH /users/:user_id/reassign_point_of_contact`.
  - Owner-reassigned Activity has a distinctive payload (`owner_reassigned: true` + `previous_owner_name` + `new_owner_name` + `actor_name`). `activity_label` helper branches on this flag and renders "Owner reassigned from X to Y by Z" instead of the regular Note label.
  - **Mobile parity choice:** Owner is displayed read-only on `MemberDetailScreen` (below the header badges); native editing is deferred to a future phase per the "near-full parity" softener and the documented web-only CRM authoring exception. The native People list has a full "People I own" toggle chip below the stage row.
  - JSON: `point_of_contact_id` + `point_of_contact_name` added to `GET /api/v1/admin/members/:id` and to every person row in both People list endpoints.
  - PoC filter param: `?owned_by_me=1` on both `/people` and `/api/v1/admin/people`. Mobile maps it to `ownedByMe` (camelCase) on the client method.

### 4.4 — Notifications

- [x] When a Person owned by user X has a significant event (email_replied, signup, subscription_ended, ~~lifecycle becomes :quiet~~), notify X.
- [x] Reuse existing notification infrastructure (whatever the Activity Feed uses).
- [x] Spec: PoC receives notification on email_replied activity; non-PoC team members do not.
- [x] **Commit:** "Notify point-of-contact on significant events"

  *Notes:*
  - New `Notifiable::PointOfContactAlert` adapter — direct push to a single recipient (the PoC), no FeedItem (the Person's Activity timeline already shows the event in context). Registered in `NotifiableFactory`.
  - `Activity.after_create` enqueues `SendNotificationsJob.perform_later(self, "PointOfContactAlert")` when (a) the kind is in `SIGNIFICANT_KINDS = %w[signup email_replied subscription_ended]` AND (b) `user.point_of_contact_id` is set.
  - **Reordered User callbacks** so `assign_default_point_of_contact!` runs *before* `log_signup_activity`. Without this, the signup Activity fires when point_of_contact_id is still nil and the signup notification gets skipped.
  - **`:quiet` lifecycle transition is deferred.** It requires a periodic job to detect users crossing the 30-day-no-visit threshold (no Activity is logged on lifecycle change). Per CONTEXT.md, `lifecycle_stage_changed` is in the V1.5+ deferred-kinds list. When that lands, add `"lifecycle_stage_changed"` to `SIGNIFICANT_KINDS` and the existing wiring covers the alert.

---

## Phase 5: Welcome drip + new automations

> **Surface:** Web-only (CRM authoring exception, per platform-parity decision 2026-05-14). No mobile screens required.

### 5.1 — Extend ProductEmailTemplate

- [x] Add new `email_type` values: `re_engagement`, `past_member_recovery`.
- [x] Update `available_merge_tags` to include any new tags needed (e.g., `{{days_since_last_visit}}`, `{{plan_canceled_on}}`).
- [x] Update `seed_defaults_for` to include defaults for new types.
- [x] **Commit:** "Add re_engagement + past_member_recovery email types"

  *Notes:*
  - `RE_ENGAGEMENT_PRODUCTS = %w[day_pass reservation]` + `PAST_MEMBER_RECOVERY_PRODUCTS = %w[membership]` — keep the cross-product matrix scoped sensibly (no office_lease re_engagement; no day_pass past_member_recovery).
  - Default delays: re_engagement 14d, past_member_recovery 30d (after grace).
  - Merge tags wired in `replace_merge_tags`: `{{days_since_last_visit}}` reads `user.activities.where(kind: [...]).maximum(:occurred_at)`; `{{plan_canceled_on}}` reads from the most recent `subscription_ended` Activity (formatted as "November 3, 2025").
  - UI index page (`product_email_templates/index.html.erb`) gains two new sections ("Re-Engagement Emails" and "Past-Member Recovery Emails") below Signup Nudge.
  - 12 new specs.

### 5.2 — Brand-stripped Cowork Tahoe seed copy

- [x] Pull Cowork Tahoe's existing onboarding/follow_up template content from production DB (read-only export).
- [x] Strip brand-specific copy (replace "Cowork Tahoe" → `{{space_name}}`, etc.).
- [x] Place in `db/seeds/welcome_drip_templates.rb`.
- [x] On first deploy + on new operator creation, seed defaults from this file.
- [x] **Commit:** "Seed welcome drip templates from Cowork Tahoe (brand-stripped)"

  *Notes:*
  - Source: Cowork Tahoe production templates id 45–50 (5 enabled rows: day_pass/membership/reservation × onboarding+follow_up) plus the office_lease + signup_nudge defaults we already had. Pulled 2026-05-15 via `heroku pg:psql -a jellyswitch-production` (read-only).
  - Stripped:
    - "Cowork Tahoe" → `{{space_name}}`
    - "David and Jamie" / "Jamie & David" / "Jamie" signatures → "The {{space_name}} team"
    - Specific addresses ("3079 Harrison Ave", "Harrison Ave & Modesto Ave") → `{{location_address}}` merge tag
    - "Cowork Tahoe app" → "our mobile app"
    - Specific room names ("Eagle Conference Room", "Publisher's Office") → "the conference room"
    - All pricing references ($15/hour, $100 Day Office, $50/hour) — operator-specific
    - PDF attachment tags (Member's Guide, Conference Room Agreement) — operator-specific files
    - "untethered.space" URLs and Round Hill / Untethered multi-location refs
  - Added bodies for all 12 combos (8 from Cowork Tahoe; 4 freshly written for office_lease + the 3 Phase 5.1 types where Cowork Tahoe had no equivalent).
  - `seed_template` is the new helper that find_or_creates the row AND writes the default body — but ONLY if the row had no body yet. Re-seeding never clobbers operator customizations. Spec'd.

### 5.3 — Wire welcome drip enqueue

- [x] In `DayPass.after_create`, if user has no prior subscription, enqueue Welcome Drip (~~subject to Spam Guard from Phase 6~~ — Spam Guard wiring deferred to Phase 6.3).
- [x] In `Crm::CreateLead` (event RSVP path), enqueue Welcome Drip — via `Lead.after_create` gated on `source == "event"`. Other Lead sources (web tour-request, referral) intentionally skip enrollment.
- [x] Spec: enqueueing happens; double-enqueue is a no-op.
- [x] **Commit:** "Auto-enqueue Welcome Drip from day-pass and event RSVP"

  *Notes:*
  - Enrollment marker is a `ProductEmailSend` row with `email_type: "welcome_drip_enrolled"`. The unique index `[sendable_type, sendable_id, email_type]` enforces idempotency at the DB level — `enroll_in_welcome_drip!` rescues `RecordNotUnique` and returns false.
  - `User#enroll_in_welcome_drip!` skips users with active subscriptions (they're already members).
  - The actual *send* of the welcome drip step emails still happens in `AutomatedWorkflowsJob#run_signup_nurture`. That handler currently filters to users with no day_passes/subscriptions/reservations — Phase 9 will broaden it to consume the `welcome_drip_enrolled` marker so day-passers + event RSVPs receive the drip. For now, enrollment is recorded but unused; once 9.1 runs, those rows become live triggers.
  - Phase 6.3 will gate `enroll_in_welcome_drip!` with `SpamGuard.eligible?`.

### 5.4 — Three new AutomatedWorkflow types

- [x] Add `day_passer_followup`, `room_reservation_followup`, `past_member_recovery` to TYPES.
- [x] Default config:
  - `day_passer_followup`: `{ days_after: 14 }`
  - `room_reservation_followup`: `{ days_after: 14 }`
  - `past_member_recovery`: `{ days_after_grace: 30 }`
- [x] Implement each in `AutomatedWorkflowsJob` — fire when conditions met, ~~respect Spam Guard~~ (TODO Phase 6.3 wires SpamGuard.eligible? checks into all 3 handlers).
- [x] Spec each.
- [x] **Commit:** "Add 3 new automation types"

  *Notes:*
  - Each handler iterates the relevant source records (DayPass / Reservation / subscription_ended Activity), gates on email_opted_out/email_bounced + has_active_subscription? + returned_since?, then sends + records via `record_send_key`.
  - `record_send_key` was broken before (didn't pass `user:`, would silently fail validation). Fixed in this commit to use `create!` with user + sendable + email_type + status + sent_at.
  - SpamGuard.eligible? check is a TODO comment in each handler — Phase 6.3 will wire it.
  - Past-member recovery's send key includes the target date so re-running on a future date doesn't re-send the same person.
  - 14 specs: model (TYPES + seed_defaults + descriptions) + job dispatch routing + day_passer_followup end-to-end (record, idempotent, template disabled, returned-since skip).

---

## Phase 6: Spam Guard

> **Surface:** Service is backend; UI is web-only (CRM authoring exception). No mobile screens required.

### 6.1 — Central service

- [x] Spec for `SpamGuard.eligible?(user, sender:, cool_down_days:)`:
  - Returns false if user is currently in any active series (`drip` campaign OR multi-step automation enrolled within the last 60 days)
  - Returns false if user received any email from `sender` operator within `cool_down_days`
  - Returns true otherwise
- [x] Implement `app/services/spam_guard.rb`.
- [x] Spec edge: transactional emails (mailers called directly, not through Campaign/Automation) bypass the guard automatically (they don't enqueue, so SpamGuard never gets consulted).
- [x] **Commit:** "Add SpamGuard service"

  *Notes:*
  - `ACTIVE_SERIES_LOOKBACK = 60.days` — anything older than that doesn't count as "currently enrolled."
  - `cool_down_days: 0` is treated as "no cool-down" (operator opted out).
  - Transactional emails (password resets, booking confirms) DO log `:email_sent` Activities (Phase 1.3.9), so they affect the cool-down check the next time SpamGuard runs. The invariant the plan calls out is that SpamGuard isn't part of the transactional send path itself — callers (Campaign/Automation) consult it; transactional mailers just send. Spec'd.
  - 12 specs cover: defensive nil handling, cool-down hit/miss/other-operator/zero, welcome-drip enrolled, expired welcome-drip enrollment, active-drip recipient, paused-campaign skip, single-campaign skip, transactional bypass.

### 6.2 — Campaign cool-down column + UI

- [x] Migration: `Campaign.cool_down_days` integer, default 30.
- [x] Add to campaign form as dropdown: 0 (off) / 30 / 60 / 90 / custom.
- [x] Update `Campaign#build_recipient_query` to apply `SpamGuard.eligible?` filter.
- [x] On campaign compose page, show "X recipients · Y excluded by Spam Guard (hover for reason)."
- [x] Spec: campaign with 100 candidates and 20 of them in active drip → recipient count = 80.
- [x] **Commit:** "Add cool-down dropdown + Spam Guard filter to Campaign"

  *Notes:*
  - `build_recipient_query(location, apply_spam_guard: true)` is the new signature. The keyword defaults to true; preview callers pass `false` to see the raw candidate pool.
  - `Campaign#spam_guard_excluded_count_for(location)` returns the diff (raw − filtered). Used by the show page to render the "· N excluded by Spam Guard" tooltip.
  - Form dropdown options: 0 (off) / 30 (default) / 60 / 90 / custom (custom appears automatically when the persisted value isn't in the list).
  - Existing `Campaign#suppression_days` column is left untouched — it's legacy with default 7 and was previously the closest concept. SpamGuard uses `cool_down_days` exclusively. Could be dropped in a future cleanup.
  - 100-candidates-20-in-drip plan-acceptance spec passes (`expect(filtered).to eq(80)`).

### 6.3 — Automation enqueue checks

- [x] In `AutomatedWorkflowsJob` and the `ProductEmailTemplate` send path, call `SpamGuard.eligible?` before sending.
- [x] If not eligible, skip + log to send_log with reason.
- [x] Spec.
- [x] **Commit:** "Apply Spam Guard to all automation send paths"

  *Notes:*
  - `AutomatedWorkflowsJob#guard_eligible?` is the shared helper — returns true if SpamGuard clears the send, otherwise logs a `ProductEmailSend` with `status: "skipped"` and a reason. Wired into all 5 handlers (re_engagement, signup_nurture, day_passer_followup, room_reservation_followup, past_member_recovery). `past_due_followup` + `booking_reminder` deliberately skipped — both are operational notifications, not marketing.
  - `SendProductEmailJob` gates every send EXCEPT `onboarding`. Onboarding is the post-purchase welcome ("your booking is confirmed") — operationally required and gating it would create confusing UX gaps right after a purchase. Follow-up + nudge + re_engagement + past_member_recovery all gate.
  - `User#enroll_in_welcome_drip!` now also consults SpamGuard before creating the enrollment marker — a user already in another drip won't get welcome-dripped on top.
  - Default `cool_down_days: 30` for all automation paths. Campaign uses its own per-campaign value from Phase 6.2.
  - Spec: 2 new tests on `AutomatedWorkflowsJob` — skipped row appears with reason; no `status: "sent"` row created when SpamGuard says no.

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
