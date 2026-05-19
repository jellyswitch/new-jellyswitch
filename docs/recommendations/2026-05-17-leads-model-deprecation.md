# Recommendation: Delete the Lead model. Build attribution instead.

**Date:** 2026-05-17 (revised after user feedback)
**Author:** David Orr (drafted with Claude)
**Status:** PROPOSED — awaiting approval
**Scope:** Rails web, Mobile, future attribution report
**Drives:** A future ADR ("Everyone in the system is already a Person; there is no Lead") + 3 implementation PRs + 1 follow-on attribution PR

## TL;DR

Lead is dead weight. **Every User is already a potential lead** — that's literally what they are if they signed up and haven't subscribed yet. Storing a separate `Lead` row to say "this Person might convert someday" is duplicating what the existence of the User row already says. Sales-pipeline status (`open / closed-won / closed-lost`) doesn't fit how a coworking space works — customers come and go based on need, not a linear funnel.

What *does* matter: **attribution**. When someone signs up for a day pass after a drip-campaign email, we should be able to say "that email caused this purchase." That capability is mostly already built — we just need a small report on top of existing data.

**Proposed:** delete the `Lead` model + table + UI + mobile screens + welcome-drip-from-event callback. Migrate `LeadNote` → the new polymorphic `Note` model (it's where ad-hoc opportunity tracking lives). Add a thin "Campaign attribution" report next.

**Net:** ~600 LOC removed, ~600 LOC added across the four PRs (most of the additions are PR 4's cookie-based attribution system, not the Lead deletion itself). One nav item gone. Two redundant models gone. No data loss in the parts that mattered.

## Reframe — what changed between v1 and v2 of this doc

| v1 said | v2 says | Why |
|---|---|---|
| Keep `Lead` model, drop the UI | Delete `Lead` model entirely | Per David: "I don't know if tracking them through a sales pipeline is totally the right approach. People use us when they need us." Status field has no audience. |
| Demote `lead.status` to a card on Person view | Drop `lead.status` entirely | Same reason. Nothing queries it; David doesn't think this way. |
| Keep `Lead.after_create` welcome-drip-from-event | Drop that callback | Per David: "Those folks shouldn't get a welcome drip. Just coming for the event." Day-pass purchase is the stronger signal and that callback already exists. |
| Three PRs to wind it down carefully | Still three PRs, but the final state is "Lead doesn't exist" not "Lead is slimmed" | Cleaner end state. |
| Did not propose attribution work | Propose follow-on PR 4 for campaign attribution | David's actual ask: "if a drip campaign goes out, and the user signs up after opening an email we know it was that email." |

## What's already built that supports the new direction

I verified all of this in the code (file paths in brackets):

- **`Activity` already records email events**: `email_sent`, `email_opened`, `email_clicked`, `email_replied` are recognized kinds [app/models/activity.rb:40-43](app/models/activity.rb:40), and the Person-view timeline has an "Emails" tab that filters to them [app/helpers/activity_timeline_helper.rb:65](app/helpers/activity_timeline_helper.rb:65).
- **Sendgrid webhook is live**: opens and clicks come in, get verified via ECDSA-P-256, write an Activity row, AND mark `CampaignSend.opened_at` / `clicked_at` per send [app/controllers/sendgrid/events_controller.rb:74-122](app/controllers/sendgrid/events_controller.rb:74).
- **`CampaignSend` model already tracks per-user delivery + engagement** for each campaign send. Joining `campaign_sends` → users → activities gives the attribution view directly.
- **Default Point-of-Contact assignment is on `User.after_create`** [app/models/user.rb:120](app/models/user.rb:120), not just `Lead.after_create` — so dropping the Lead callback doesn't break PoC defaulting.
- **The welcome drip has two triggers today**: (1) `Lead.after_create` when `source: "event"` [app/models/lead.rb:25-37](app/models/lead.rb:25), and (2) `DayPass.after_create` [app/models/day_pass.rb:48-59](app/models/day_pass.rb:48). Dropping the first leaves the second — the stronger signal — intact.
- **Polymorphic `Note` model landed today** [app/models/note.rb](app/models/note.rb) (migration `20260517130223_create_notes.rb`). Notes can attach to User directly. The rare "I need to remember this person is interested in office space" case lives here as a free-form note, not a structured Lead.

## What gets deleted, what survives, what gets added

### Delete
- `Lead` model + `leads` table + `LeadPolicy`
- `LeadNote` model + `lead_notes` table (after backfill to `Note`)
- `Operator::LeadsController`, `Operator::LeadNotesController`
- `Api::V1::Admin::LeadsController`, `Api::V1::Admin::LeadNotesController`
- All Lead views (`app/views/operator/leads/*`)
- Mobile `AdminLeadsScreen.js`, `adminLeadsAPI`, related Hamburger/More/Navigator entries
- (No public web tour-request form exists in this codebase — only `mailto:` links on operator landing pages. Earlier drafts of this doc incorrectly assumed one existed; corrected 2026-05-17 after re-audit.)
- `Crm::CreateLead` interactor + `Events::RegisterAndGoing` swaps to a no-Lead variant (just creates User + RSVP)
- The `Lead.after_create :enroll_user_in_welcome_drip_from_event` callback (welcome drip still fires from day-pass purchase)
- Search controller's `lead.status` projection in admin search JSON

### Keep
- The Person view, lifecycle_stage, activity timeline, People list with stage chips — **all of the CRM V1 work stays.** David said "I kinda like the system we are creating."
- `Note` model for free-form annotations (ad-hoc opportunity tracking)
- `DayPass.after_create` welcome-drip trigger (the strong signal)
- The Sendgrid event webhook and `CampaignSend` engagement tracking
- The "Emails" tab on the Person-view timeline

### Add
- **Campaign attribution report** (PR 4, follow-on): "For campaign X sent on date Y, how many recipients opened, clicked, and went on to buy a day pass / start a membership within N days?" SQL-level join from `campaign_sends` → `users.day_passes` and `users.subscriptions`, filtered by `created_at > campaign_send.created_at AND created_at < campaign_send.created_at + N.days`.
- **Per-Person attribution chip on the day-pass / subscription activity row.** When the timeline shows "Bought a day pass" or "Started membership", and the user had an email open/click within the last 30 days, append a small chip: "Likely from email: <subject>". Visual only — surfaces the correlation operators already have in their heads.

## Scope — three PRs in order, plus a follow-on

### PR 1 — Migrate LeadNote → Note (Rails + Mobile)
Same as v1. Required first because Add Note flows currently route through LeadNote.

- Decide: rich-text vs plain-text on `Note.body` (recommend rich-text via `has_rich_text :body` to preserve formatting on backfill).
- Add `Note.after_create :log_activity` (kind: `:note`, only when `notable_type == "User"`).
- Backfill rake task: `LeadNote` → `Note`. Idempotent. Source field: `lead_note.content.body`.
- `Operator::UsersController#add_note` writes to `Note` directly, no more `Lead.first_or_create` workaround.
- Person-view "Notes" tab reads from `Note` instead of `LeadNote`.
- Mobile API: switch from `adminLeadsAPI.addNote` to `adminMembersAPI.addNote`.
- **No deletions yet.** LeadNote is left as dead code for one prod-bake cycle.
- **~250 LOC added, ~50 LOC changed.**

### PR 2 — Delete Leads UI + welcome-drip-from-event callback (Rails + Mobile)
- Delete the 4 controllers, all views, the Leads route, the People-subnav Leads tab.
- Delete mobile `AdminLeadsScreen`, `adminLeadsAPI`, nav entries.
- Replace `Events::RegisterAndGoing` with `Events::RegisterAndGoingWithoutLead` (or just inline the two remaining interactors).
- Add deprecation log lines on the Lead model (so any sneaky callers show up in Honeybadger before PR 3).
- **~400 LOC removed, ~50 LOC added.**

### PR 3 — Drop the Lead + LeadNote models + tables (Rails)
Wait ≥7 days after PR 2 in prod with zero deprecation log hits.

- `drop_table :lead_notes`, `drop_table :leads` (reversible migrations).
- Delete `app/models/lead.rb`, `app/models/lead_note.rb`, all factories, all specs.
- Final import cleanup.
- **~200 LOC removed.**

### PR 4 (follow-on) — Cookie-based attribution + Campaign report (Rails)
Not blocked by PRs 1-3 but easier to scope once they're in. Bigger than originally drafted because David's preferred approach is cookie-based (precise) rather than time-window (probabilistic).

**Tracking infrastructure:**
- New `Tracking::ClicksController` at `GET /t/click?cs=<campaign_send_id>&to=<destination>`. Marks `CampaignSend.clicked_at`, logs `Activity(:email_clicked)`, sets first-party cookie `js_attribution = { campaign_send_id, clicked_at }` with 60-day expiry, 302-redirects to destination.
- Mailer / template-render layer: rewrite every link in outgoing Sendgrid emails to go through the tracking redirect. Probably in `ProductEmailSend#deliver` or wherever rendered HTML is built. ~50 LOC, one-time change.
- Cookie-set helper safe against open redirects: validate `to` parameter is on a whitelisted operator host.

**Conversion attribution:**
- Add `attributed_to_campaign_send_id` column to `users`, `day_passes`, `subscriptions` (nullable). Set on create from cookie if present.
- After-create hooks on those three models: if cookie present and `clicked_at` within attribution window (60 days), persist the attribution. Log `Activity(:conversion, payload: { attributed_to_campaign_send_id, source: "click" })`.
- Fallback for users without a click cookie: at conversion time, look back 14 days for `:email_opened` activities for the same user; attribute to the most recent if found, with `source: "open_inferred"`.

**Reporting:**
- New report: `app/views/operator/reports/campaign_attribution.html.erb` (or tab on existing Reports). For each campaign: recipients, open rate, click rate, **attributed day-pass conversions, attributed subscription conversions, total revenue attributed**.
- Per-Person attribution chip on the activity timeline: when rendering a `day_pass` or `subscription_start` activity with an `attributed_to_campaign_send_id`, surface the source campaign as a chip ("From email: Welcome Drip Day 3").

**Specs:** click endpoint marks CampaignSend, sets cookie, redirects to whitelist host only; open-redirect attempts rejected; conversion happens with cookie → attributed; conversion happens without cookie but with recent open → attributed via fallback; conversion with neither → null attribution; attribution window expiry honored.

- **~500-600 LOC added.** Three migrations (one per attributed table).

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| Some real lead-tracking workflow that David forgot about | Low — David explicitly said the cases are rare | Notes serve them. If a structured field is needed later, add `User.opportunity_status` as a single string column. Easy to add, harder to maintain forever. |
| `Lead.source = "web"` data on the tour-request form is silently lost | Medium | PR 2 must decide what happens to the public tour-request form. If we keep it as User+Activity, the source attribution survives in the activity payload. |
| Welcome drip silently stops enrolling someone we actually wanted enrolled | Low — only event-via-cold-signup is affected | New Activity (kind: `:event_signup`) captures the funnel touch for future analysis; if we ever want to re-add the enrollment, it's a one-line callback. |
| Honeybadger floods with `NameError: Lead` from a forgotten code path | Low — the audit found everything | Deprecation log lines in PR 2 catch this before PR 3 ships. |
| LeadNote backfill drops a row or corrupts rich text | Low (idempotent, audit logged) | Rake task counts before/after; PR 3 only drops the table after ≥7 days in prod. |
| Operators were using the Leads index daily without realizing | Low — it has no filters and duplicates People | Quick check: pull last 30 days of `production` logs for hits on `GET /leads`. If non-trivial, communicate the change in release notes. |

## Decisions made 2026-05-17

1. **Rich text on Notes** → YES. `Note.body` gets `has_rich_text` in PR 1. LeadNote → Note backfill preserves formatting via `lead_note.content.body`.
2. **Attribution approach** → Cookie-based, NOT time-window. Every Sendgrid email link goes through a tracking redirect that sets a first-party `js_attribution` cookie on click. When a conversion happens (User created, DayPass purchased, Subscription started), the cookie is read and `Activity(:conversion, payload: { attributed_to_campaign_send_id })` is logged with precision. Fallback path: probabilistic match against the most recent `:email_opened` activity within 14 days if no cookie. See revised PR 4 scope.
3. **Archive `leads` + `lead_notes` before drop** → YES. `pg_dump` snapshot to S3 before PR 3 ships. Cheap insurance.

## Alternative considered and rejected: "tag the Person with `:potential_lead`"

Some teams replace Lead with a tag/label system. Why not here:
- A tag system is general infrastructure that doesn't exist yet. Building it just for this is overkill.
- The Note model + lifecycle_stage already give you "this person is a potential lead" implicitly (anyone whose lifecycle_stage is `:signup_only`, `:tour_taker`, `:day_passer`, or `:quiet` is by definition a potential lead).
- If a structured "opportunity I'm working" flag is needed later, a single string column on `User` is half a day's work. Not worth building tags speculatively.
