# Day Pass Bundle — Notifications & Automation Plan (Plan 6)

> Use superpowers:subagent-driven-development + strict TDD. Closes two gaps the exploration found: (A) day-passer-followup automation SPAMS active bundle users, and (B) bundle purchase is completely silent (no admin feed/push). Specs: `PATH="$HOME/.rbenv/shims:$PATH" bundle exec rspec <path>`.

---

## Task 1: stop the automation spam — exclude bundle-sourced day passes from day-passer follow-up

**Problem:** `AutomatedWorkflowsJob#run_day_passer_followup` keys off `DayPass` rows N days old. Each *entry-burn* mints a `DayPass`, so an active bundle holder with staggered visits gets a re-engagement email per stale entry-pass. Single-day-pass re-engagement should not target bundle holders.

**Marker:** an entry-minted `DayPass` is referenced by a `DayPassBundleRedemption` (`kind: "entry"`, `day_pass_id` set). That's the "bundle-sourced" signal — no new column needed.

**Files:** `app/models/day_pass.rb` (scope); `app/jobs/automated_workflows_job.rb` (use the scope); tests in `spec/models/day_pass_spec.rb` + `spec/jobs/automated_workflows_job_spec.rb` (or wherever the job is specced).

- [ ] **Step 1 — Read** `app/jobs/automated_workflows_job.rb` around `run_day_passer_followup` to see the exact `DayPass` query it builds.
- [ ] **Step 2 — Failing spec.**
  - Model scope spec in `spec/models/day_pass_spec.rb`: create a plain `DayPass` and a bundle-sourced one (a `DayPassBundleRedemption` with `kind: "entry"`, `day_pass: dp`). `DayPass.not_bundle_sourced` returns only the plain one; `DayPass.bundle_sourced` only the other.
  - Job-level spec: a user whose ONLY day pass N-days-ago is bundle-sourced does NOT receive the day-passer follow-up; a user with a plain day pass N-days-ago does. (Mirror the existing day-passer-followup spec setup; assert the re-engagement mailer/enrollment is/ isn't invoked — stub the mailer/`ProductEmailTemplate` send the way the existing spec does.)
- [ ] **Step 3 — Implement.**
  - `app/models/day_pass.rb`:
```ruby
  scope :bundle_sourced, -> {
    where(id: DayPassBundleRedemption.where(kind: "entry").select(:day_pass_id))
  }
  scope :not_bundle_sourced, -> {
    where.not(id: DayPassBundleRedemption.where(kind: "entry").select(:day_pass_id))
  }
```
  - In `run_day_passer_followup`, apply `.not_bundle_sourced` to the `DayPass` relation it selects candidates from. (Single subquery — no N+1.)
- [ ] **Step 4 — Run green** (scope spec + job spec + the existing automation specs to confirm no regression). **Step 5 — Commit:**
```
git add app/models/day_pass.rb app/jobs/automated_workflows_job.rb spec/
git commit -m "fix: day-passer follow-up automation skips bundle-sourced passes (no spam to bundle holders)"
```

---

## Task 2: bundle purchase is no longer silent — admin feed item + push

**Problem:** `CreateBundle` only does save + invoice + charge — no `CreateNotifications`, and `DayPassBundle` isn't in `NotifiableFactory`. The single-day-pass flow notifies admins (push + feed item "X purchased a day pass"). Mirror that for bundles.

**Files:** `app/object_factories/notifiable_factory.rb`, new `app/.../notifiable/day_pass_bundle.rb` (match where `Notifiable::DayPass` lives), `app/interactors/billing/day_pass_bundles/create_bundle.rb` + `save_bundle.rb` (set `context.operator`/`context.location` if not already), tests.

- [ ] **Step 1 — Read** `Notifiable::DayPass` (the class `NotifiableFactory.for(day_pass)` returns) and `Billing::DayPasses::CreateNotifications` to see exactly what a day-pass purchase notifies (admin push recipients + `FeedItemCreator` blob shape), then mirror it for a bundle.
- [ ] **Step 2 — Failing spec.** An interactor/integration spec: calling `Billing::DayPassBundles::CreateBundle` (out_of_band, Stripe stubbed as the existing create_bundle spec does) creates a **feed item** for the bundle purchase (assert a `FeedItem` row with a bundle/`day-pass-bundle` type + the buyer name + pack name) and notifies admins (assert the push path is invoked — stub/spy the notifier like the day-pass notification spec). Also assert an `Activity`-or-feed visibility record exists for the purchase (whichever the day-pass flow uses).
- [ ] **Step 3 — Implement.**
  - `Notifiable::DayPassBundle` mirroring `Notifiable::DayPass#notify`: admin push to `operator.users.relevant_admins_of_location(location)` + `FeedItemCreator.create_feed_item(type: "day-pass-bundle", ...)` with the buyer name + `"purchased a #{quantity}-Pass"` style message. Register it in `NotifiableFactory.for`.
  - Add a `Billing::DayPassBundles::CreateNotifications` step (mirror `Billing::DayPasses::CreateNotifications` — it calls `NotifiableFactory.for(context.notifiable).notify`) to the `CreateBundle` organizer, AFTER the charge step. Ensure `context.operator`/`context.location`/`context.notifiable = day_pass_bundle` are set (SaveBundle/CreateStripeInvoiceForBundle already set notifiable; confirm operator+location are in context).
- [ ] **Step 4 — Run green** (new spec + the existing create_bundle/purchase specs — confirm the charge path still works and the notification doesn't break out_of_band). **Step 5 — Commit:**
```
git add app/object_factories/notifiable_factory.rb app/**/notifiable/day_pass_bundle.rb app/interactors/billing/day_pass_bundles/ spec/
git commit -m "feat: bundle purchase notifies admins (feed item + push), mirroring day-pass purchase"
```

---

## Final gate (Plan 6)
- [ ] Bundle + automation + notification specs green; existing day-pass automation + notification specs green (no regression).
- [ ] Scope note: deferred (not this plan) — a *bundle-specific* re-engagement automation (e.g. "bundle expiring / passes unused"), buyer-facing purchase email, and guest-check-in Activity logging. Flag these; don't build them here.
