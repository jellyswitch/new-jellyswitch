# Day Pass Bundle — Buyer Emails, Feed Detail & Revenue Plan (Plan 7)

> Continues the bundle series (Plans 5b/6). Closes the three gaps surfaced in the field:
> (1) bundles have **no buyer-facing lifecycle emails** (Plan 6 deferred this), (2) the bundle **feed item shows no price and no Approve action** (Plan 6 created it bare — admin had to approve from the member's account), (3) **"Who's coming today" revenue is wrong** (bundle sales uncounted; prepaid burns double-counted).
>
> Use superpowers:subagent-driven-development + strict TDD. Specs: `PATH="$HOME/.rbenv/shims:$PATH" bundle exec rspec <path>`.
> Branch: `feature/day-pass-bundle-buyer-emails` (off current `origin/main`; the old `feature/day-pass-bundles` is merged + stale — do not reuse). Backend-only — **the mobile app needs zero changes** (its feed Amount + Approve controls are data-driven and light up once the API emits the fields).
>
> Decisions captured in `CONTEXT.md` (Day Pass Bundle) and `docs/adr/0009-bundle-revenue-recognized-at-sale.md`. Glossary rule: bundle passes are **"passes / passes remaining"**, never "credits".

---

## Task 1: "Who's coming today" — cash-basis bundle revenue

**Problem:** `Api::V1::Admin::TodaysActivityController` sums `todays_day_passes.joins(:day_pass_type).sum(:amount_in_cents)`. A bundle-sourced entry mints a `DayPass`, so each prepaid walk-in **double-counts** against the sale — and the actual bundle **sale** is never counted (the endpoint only sums day passes, reservations, new subscriptions). Per ADR 0009: recognize the sale on its purchase day at the pack price (day_pass_type.amount_in_cents); a burn is $0.

- [ ] **Step 1 — Failing request spec** (`spec/requests/api/v1/admin/todays_activity_spec.rb`), three assertions:
  - A **bundle purchased today** adds its **pack price** (`day_pass_type.amount_in_cents`) to `revenue` (never `× quantity`).
  - A **bundle-sourced entry** today (a `DayPass` minted via `ConsumeOnEntry`, i.e. matched by `DayPass.bundle_sourced`) adds **$0** to `revenue`.
  - That same bundle holder **still appears** in the `day_passes` attendee list (excluded from revenue only, never from who-is-here).
- [ ] **Step 2 — Implement** in `todays_activity_controller.rb`:
  - The day-pass revenue term **already** uses `.not_bundle_sourced` (shipped as adversarial fix "I1"), and bundle-sourced rows already render `cost: 0`. The only missing half is the **sale**.
  - Add a bundle-sale term to `revenue_cents` → `DayPassBundle.where(operator: current_tenant, location: location, purchased_at: today.all_day).joins(:day_pass_type).sum('day_pass_types.amount_in_cents')`. This is the flat pack price (the exact one-time charge per `create_stripe_invoice_for_bundle`), summed exactly like the existing day-pass/plan terms — **not** the invoice (Invoice has no `amount` column; it has `amount_due`/`amount_paid`).
  - Leave the `day_passes:` attendee array untouched (bundle holders keep showing).
- [ ] **Step 3 — Commit:** `fix(billing): cash-basis bundle revenue in today's activity (count sale, zero the burn)`

---

## Task 2: Bundle feed item — Amount + Approve (backend; mobile auto-lights-up)

**Problem:** Plan 6 created `Notifiable::DayPassBundle` → a feed item typed `"day-pass-bundle"` with only a message string. On **web** there's no partial (falls through to nothing); on **mobile** the `/admin/feed` serializer emits no `amount`/`requires_approval`, so the universal Amount + Approve controls stay hidden. Target: match day-pass / membership.

- [ ] **Step 1 — Failing model spec** (`spec/models/feed_item_spec.rb`): a `"day-pass-bundle"` feed item is `requires_approval?`.
  - **Implement:** add `"day-pass-bundle"` to `FeedItem#requires_approval?`.
- [ ] **Step 2 — Failing request spec** (`spec/requests/api/v1/admin/feed_spec.rb`): `GET /admin/feed` for a bundle purchase returns a JSON item with `amount` == `bundle.day_pass_type.amount_in_cents`, `requires_approval: true`, `user_id`, `user_approved`, plus `day_pass_type` name and pack `quantity`.
  - **Implement:** in `Api::V1::Admin::FeedController#feed_item_json`, add `when 'day-pass-bundle'`:
    ```ruby
    when 'day-pass-bundle'
      bundle = DayPassBundle.find_by(id: fi.blob['day_pass_bundle_id'])
      base.merge(
        action_text: "bought a #{bundle&.quantity_purchased}-Pack",
        day_pass_type: bundle&.day_pass_type&.name,
        amount: bundle&.day_pass_type&.amount_in_cents,   # flat pack price = the charge (ADR 0009); matches day-pass item
        requires_approval: true,
      )
    ```
- [ ] **Step 3 — Web partial** `app/views/operator/feed_items/_day_pass_bundle_feed_item.html.erb`, mirroring `_day_pass_feed_item.html.erb`: **Pack** (`quantity_purchased`), **Amount** (`number_to_currency(bundle.day_pass_type.amount_in_cents / 100.0)`), **Type** (`day_pass_type.name`), **Expires** (`expires_at` or "Never"). Read the bundle via `feed_item.blob['day_pass_bundle_id']`. (Add a `day_pass_bundle` accessor on `FeedItem` if the day-pass partial uses one.)
- [ ] **Step 4 — Manual mobile verification (no code):** with the API emitting the fields, confirm the feed card shows `$X.XX` and an **Approve** button for an unapproved buyer, and that Approve calls `POST /admin/members/:id/approve`. Note result in the PR.
- [ ] **Step 5 — Commit:** `feat(feed): bundle purchase shows amount + approve on web and mobile`

---

## Task 3: Buyer lifecycle emails (onboarding → review → replenishment)

**Problem:** Buying a bundle is silent to the buyer (Plan 6 deferred this). Per CONTEXT.md, a bundle buyer is a **customer, not a lead** — **no welcome-drip enrollment** — and gets three bundle-native emails on a **dedicated `day_pass_bundle` product_type** whose default copy is **cloned from the day-pass templates**.

Email → trigger map (the triggers are bundle events, not day-anchored delays):
| email_type | Trigger | Mailer |
|---|---|---|
| `onboarding` | bundle purchase | `product_onboarding_email` |
| `follow_up` (review / "how are we doing") | **first `entry` redemption** | `product_follow_up_email` |
| `replenishment` (**new email_type**) | `passes_remaining` reaches **0** | `product_follow_up_email` (carries membership upsell) |

- [ ] **Step 1 — Template plumbing.** Failing `product_email_template_spec.rb`: a seeded location has enabled-able `day_pass_bundle` templates for `onboarding`, `follow_up`, `replenishment`, and bundle merge tags resolve.
  - **Implement** in `ProductEmailTemplate`:
    - Add `"day_pass_bundle"` to `PRODUCT_TYPES`; add `"replenishment"` to `EMAIL_TYPES`.
    - `DEFAULT_SUBJECTS`: `day_pass_bundle_onboarding` ("Your {{quantity}}-Pack is ready — here's how it works"), `day_pass_bundle_follow_up` ("How was your visit?"), `day_pass_bundle_replenishment` ("You're out of passes — grab another pack").
    - `seed_defaults_for`: include `day_pass_bundle` (onboarding + follow_up + replenishment). **Do not** add it to `RE_ENGAGEMENT_PRODUCTS`.
    - `product_label` → "Day Pass Bundle".
    - `available_merge_tags` + `replace_merge_tags`: add a `day_pass_bundle` branch emitting `{{quantity}}`, `{{passes_remaining}}`, `{{expires_at}}` (NOT `{{date}}` — a bundle has no single day).
  - Confirm the settings UI auto-lists the new product_type (the index view iterates `@onboarding_templates` etc. — no view edit expected; verify the `replenishment` group renders, add a group section if absent).
- [ ] **Step 2 — Onboarding on purchase.** Failing interactor spec: `Billing::DayPassBundles::CreateBundle` enqueues the **onboarding** email (and does **not** enroll the buyer in the welcome drip).
  - **Implement** new stage `Billing::DayPassBundles::ScheduleBundleEmails` (mirror `Billing::DayPasses::ScheduleDayPassEmails`) appended to the `CreateBundle` organizer: set `product_email_sendable = bundle`, `product_email_type = "day_pass_bundle"`, `product_email_user = bundle.user`, then `ScheduleProductEmails.call`. **Schedule only `onboarding`** here — `follow_up`/`replenishment` are event-fired (Steps 4–5), so guard `ScheduleProductEmails` to skip the time-delayed follow_up for `day_pass_bundle` (or branch `calculate_follow_up_time` to no-op for bundles). Explicitly assert **no `enroll_in_welcome_drip!`**.
- [ ] **Step 3 — SendProductEmailJob support.** Failing job spec.
  - **Implement:** `resolve_location` → `when DayPassBundle then sendable.location`; route `email_type` "replenishment" → `product_follow_up_email`; log `ProductEmailSend` as today (already generic).
- [ ] **Step 4 — Review email on first visit.** Failing spec on `DayPassBundle#burn!`: the **first `entry` redemption** enqueues `SendProductEmailJob(..., "day_pass_bundle", "follow_up", user)`; a **second** entry does not; a **guest** burn does not trigger it.
  - **Implement** in `burn_locked!` (kind `:entry` only): if this is the first `entry` redemption for the bundle, enqueue the review email behind `SpamGuard` + a once-per-bundle send key (`"bundle_review_#{bundle.id}"`).
- [ ] **Step 5 — Replenishment email at zero.** Failing spec: when `burn!` drops `passes_remaining` to `0`, enqueue `SendProductEmailJob(..., "day_pass_bundle", "replenishment", user)`; not enqueued while `> 0`; not re-sent if an `admin_restore` then re-burn hits 0 again (send key `"bundle_replenishment_#{bundle.id}"`).
  - **Implement** in `burn_locked!` after the decrement: `if passes_remaining.zero?` enqueue behind `SpamGuard` + the send key.
- [ ] **Step 6 — Commit (per sub-task, e.g.):** `feat(email): bundle buyer lifecycle — onboarding, first-visit review, zero-balance replenishment`

---

## Final gate (Plan 7)

- [ ] All new specs green; full bundle suite still green.
- [ ] Manual: mobile feed shows Amount + Approve for an unapproved bundle buyer; web feed renders the new partial.
- [ ] Manual: staging — buy a bundle (onboarding arrives, buyer NOT in welcome drip), first door-burn (review arrives), burn to zero (replenishment arrives); confirm SpamGuard de-dupes.
- [ ] `CONTEXT.md` (Day Pass Bundle: revenue / lifecycle emails / replenishment) and ADR 0009 are committed alongside.
- [ ] **Scope note — deferred (not this plan):** the **expiration-reminder** email (option C — nightly expiry sweep, location-conditional per ADR 0008) and guest-check-in Activity logging. Flag for a future Plan 8; don't build here.
```
git add -A && git commit -m "docs: Plan 7 — bundle buyer emails, feed detail, cash-basis revenue (+ADR 0009)"
```
