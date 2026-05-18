# Tour Request Widget — Design Spec

**Date:** 2026-05-17
**Status:** Approved, ready for implementation plan
**Scope target:** ~600 LOC, one PR, no mobile work
**Builds on:** `project_tour_request_widget.md` (deferred plan from 2026-05-17 session)

## Goal

Give operators a Jellyswitch-hosted tour-request form they can drop into their external marketing site (WordPress / Squarespace / Webflow). Submissions land directly in the Person system as `User + Activity(:tour_request)` and notify the operator's admins + the requested location's managers. Spam-hardened via honeypot + Rack::Attack + Cloudflare Turnstile.

This replaces the current pattern (Untethered iframes the operator subdomain root — a generic "Welcome to [location] / Sign Up" page — as a stand-in for a tour form). Untethered swaps one `src=` URL and gets a real funnel.

## Out of scope (Phase 2 / deferred)

- JS widget (`<script src="…/widget.js">`) with custom styling — Phase 2.
- Per-operator Turnstile sitekeys — Phase 2.
- Mobile app embedding — never (the operator pastes HTML/iframe on their marketing site).
- Campaign attribution reporting (separate PR 4 of Lead deprecation work).

## Non-goal: Lead deprecation prerequisite

The original memory said this work should land after Lead deprecation PRs 1-3 are in prod. **It hasn't.** David's call (this session): ship the widget now anyway because it's strictly additive — creates `User + Activity(:tour_request)` rows, doesn't touch `Lead`. No conflict when Lead deprecation lands later.

## Architecture overview

```
External marketing site (WordPress, Squarespace, etc.)
  │
  │  <iframe src="https://app.jellyswitch.com/embed/tour_request/<subdomain>">
  ▼
GET  /embed/tour_request/:subdomain          → renders form HTML (frame-able)
POST /embed/tour_request/:subdomain          → handles submission
  │
  ├─ honeypot check (silent drop)
  ├─ Rack::Attack rate limit (5/min per IP on /embed/*)
  ├─ Cloudflare Turnstile token verification
  ├─ User.find_or_create_by(email, operator)
  ├─ Activity.log(kind: :tour_request, payload: { message, source, location_id })
  ├─ SendNotificationsJob.perform_later(activity, "TourRequestAlert")
  │     → push + email fan-out to operator admins + location managers
  └─ render thank-you (Rails-hosted or redirect)
```

The submission endpoint is **public** (no CSRF token from the cross-origin iframe POST), so it's hardened at three layers (honeypot, rate limit, Turnstile) and the create path is strictly additive (no destructive operations).

## URL surface

| Verb   | Path                                                     | Purpose                                       |
|--------|----------------------------------------------------------|-----------------------------------------------|
| GET    | `/embed/tour_request/:subdomain`                         | Render embeddable form (iframe target)        |
| GET    | `/embed/tour_request/:subdomain/locations/:location_id`  | Same, pinned to one location                  |
| POST   | `/embed/tour_request/:subdomain`                         | Submit (location_id in body)                  |
| GET    | `/embed/tour_request/:subdomain/thank_you`               | Hosted confirmation page                      |
| GET    | `/operator/settings/tour_widget`                         | Operator admin UI (snippet generator)         |
| PATCH  | `/operator/settings/update_tour_widget`                  | Persist thank_you_redirect_url etc.           |

All `/embed/*` routes:
- Skip CSRF (`skip_before_action :verify_authenticity_token`)
- Skip authentication (public)
- Allow framing (`X-Frame-Options: ALLOWALL` for `/embed/*` only — other routes keep their default `SAMEORIGIN` / `DENY`)
- Set permissive CORS for the POST path (the HTML snippet posts cross-origin)

## Data model changes

### `Activity::KINDS` — add `:tour_request`
```ruby
KINDS = %w[
  signup tour tour_request checkin door_punch reservation
  day_pass subscription_started subscription_ended
  payment_succeeded payment_failed note
  email_sent email_opened email_clicked email_replied
].freeze
```

### `ActivityTimelineHelper::KIND_GROUPS` — add `:tour_request` to the existing **Tours** bucket
So existing UI ("Tours" tab in the Person timeline) picks it up automatically.

### `Operator` — three new columns
```ruby
# add_column :operators, :tour_widget_enabled,            :boolean, default: false, null: false
# add_column :operators, :tour_widget_thank_you_url,      :string
# add_column :operators, :tour_widget_intro_html,         :text
```

`tour_widget_enabled` defaults false. Operators opt in via Settings before the iframe will render anything but a "Tour requests are not configured" placeholder. This is the safety knob — no operator gets an active public endpoint until they flip it on.

### No Operator-side Turnstile config — single Jellyswitch-owned sitekey + secret in ENV (`TURNSTILE_SITEKEY`, `TURNSTILE_SECRET`).

## Controllers

### `Embed::TourRequestsController` (new, public)
- `before_action :load_operator_by_subdomain` (404 if subdomain missing / `tour_widget_enabled = false`)
- `before_action :set_acts_as_tenant`
- `skip_before_action :verify_authenticity_token`
- `after_action :allow_framing` (sets `X-Frame-Options` header)
- Actions: `show` (GET form), `create` (POST), `thank_you`

Submission flow (`create`):
1. Honeypot: if `params[:_hp].present?` → return `head :ok` silently (no DB write, no log spam).
2. Turnstile: call `Turnstile::Verifier.call(token: params["cf-turnstile-response"], remote_ip: request.remote_ip)`. If invalid → `unprocessable_entity` with `errors[:base] = "Please retry the captcha"`.
3. Validate `params[:name]`, `params[:email]`, `params[:location_id]` (required if operator has >1 visible location).
4. `user = User.find_or_initialize_by(email:, operator:)`. If new: set `name`, `original_location_id`, skip `phone` requirement (set `admin_created: true` to bypass — they didn't sign up themselves).
5. On save: `Activity.log(user:, operator:, kind: :tour_request, occurred_at: Time.current, subject: location, payload: { message:, source: "widget", referrer: request.referer })`.
6. `SendNotificationsJob.perform_later(activity, "TourRequestAlert")`.
7. If `operator.tour_widget_thank_you_url.present?` → redirect there (303). Else → render `thank_you` view.

### `Operator::SettingsController#tour_widget` (existing controller, new actions)
- `tour_widget` (GET): renders snippet generator
- `update_tour_widget` (PATCH): persists `tour_widget_enabled`, `tour_widget_thank_you_url`, `tour_widget_intro_html`

## Models / services

### `Turnstile::Verifier` (new, ~30 LOC)
Service object wrapping `Faraday` (already in Gemfile) POST to `https://challenges.cloudflare.com/turnstile/v0/siteverify`. Returns `success: true/false`.

**Behavior matrix:**
| `TURNSTILE_SECRET` set? | Token verifies? | Network error? | Result |
|---|---|---|---|
| no (dev/test) | n/a | n/a | `success: true` (short-circuit, no network call) |
| yes | yes | no | `success: true` |
| yes | no | no | `success: false` |
| yes | n/a | yes | `success: false` + `Honeybadger.notify` (fail closed — don't silently let traffic through if Turnstile is down) |

### `Notifiable::TourRequestAlert` (new, ~40 LOC)
Parallels `Notifiable::PointOfContactAlert`. Recipients:
```ruby
def recipients
  activity = __getobj__
  location = activity.subject
  ops_admins = activity.operator.users.where(role: User::ADMIN)
  loc_gms   = location ? activity.operator.users.where(
                role: [User::GENERAL_MANAGER, User::COMMUNITY_MANAGER],
                current_location_id: location.id
              ) : User.none
  (ops_admins + loc_gms).uniq
end

def message
  "New tour request: #{__getobj__.user.name} (#{__getobj__.payload['message']&.truncate(40)})"
end

def deep_link_data
  { type: "user", resource_id: __getobj__.user_id, path: "/users/#{__getobj__.user_id}" }
end

def should_send_notification?
  __getobj__.kind.to_s == "tour_request"
end
```

### `TourRequestMailer#new_request` (new, ~30 LOC + view)
Email to each recipient. Sent from `Notifiable::TourRequestAlert` by overriding `notify` to call `super` (push) then iterating `recipients` and queueing `TourRequestMailer.with(user: r, activity: __getobj__).new_request.deliver_later`. One mailer call per recipient. Subject: `"New tour request: <name>"`. HTML + text views render: name, email, phone (if given), location name, message body, and a link to `https://<subdomain>.jellyswitch.com/users/:id` for the recipient to open the Person profile.

### `User.find_or_initialize_by(email, operator)` — already supported via `acts_as_tenant`. Make sure we don't fail because of phone presence validation on create — set `admin_created: true`.

## Spam mitigation (defense in depth)

| Layer | Mechanism | Reject behavior |
|---|---|---|
| 1 | Honeypot field `_hp` (CSS-hidden, `tabindex=-1`, `autocomplete=off`) | Silently return 200, no DB write |
| 2 | Rack::Attack `/embed/*` throttled to 5 req/min per IP | HTTP 429 with friendly retry message |
| 3 | Cloudflare Turnstile token required on submit | HTTP 422 with "Please retry the captcha" |
| 4 | Email format validation (Rails default) | HTTP 422 with field error |

Rack::Attack will be a new initializer at `config/initializers/rack_attack.rb` (none exists today). Just the throttle rule for `/embed/*`. Document the gem add in the PR.

## Operator settings UI (`/operator/settings/tour_widget`)

Lives under existing Settings tab nav. Shows:

1. **Enable toggle** — "Allow public tour requests" checkbox (binds `tour_widget_enabled`).
2. **Live preview** — Renders the form inline using the same partial the public endpoint serves (so the operator sees exactly what gets embedded).
3. **Two snippet boxes side-by-side**, each with a copy-to-clipboard button:

   **Iframe (recommended):**
   ```html
   <iframe src="https://app.jellyswitch.com/embed/tour_request/<subdomain>"
           width="100%" height="600"
           style="border: none;"
           title="Request a tour">
   </iframe>
   ```

   **HTML form (advanced):**
   Form with `action` pointed at the POST endpoint, honeypot included, Turnstile widget script reference, all fields.

4. **Location dropdown** — "Pin this snippet to a specific location?" If selected, regenerates both snippets with `/locations/:location_id` in the URL. Useful for operators who maintain a separate marketing page per location.

5. **Thank-you redirect URL** — text input, optional. Blank = use Rails-hosted thank-you page.

6. **Intro HTML** — small rich-text area (`has_rich_text :tour_widget_intro_html` — Action Text) shown above the form fields in the iframe. Lets operator put "Tell us about your team and we'll set up a tour" etc.

Reachable from Settings nav (new "Tour Widget" link added to `app/views/operator/settings/_tab_layout.html.erb` or the existing tab partial).

## The form itself

Rendered by `app/views/embed/tour_requests/_form.html.erb` (also reused inside the Settings preview):

```erb
<form action="<%= submission_url %>" method="post" class="js-tour-request-form">
  <%= operator.tour_widget_intro_html if operator.tour_widget_intro_html.present? %>

  <% if @locations.size > 1 && @pinned_location.nil? %>
    <label>Location *</label>
    <select name="location_id" required>
      <% @locations.each do |loc| %>
        <option value="<%= loc.id %>"><%= loc.name %></option>
      <% end %>
    </select>
  <% elsif @pinned_location %>
    <input type="hidden" name="location_id" value="<%= @pinned_location.id %>">
  <% end %>

  <label>Your name *</label>
  <input type="text" name="name" required>

  <label>Email *</label>
  <input type="email" name="email" required>

  <label>Phone</label>
  <input type="tel" name="phone">

  <label>What are you looking for?</label>
  <textarea name="message" rows="4"></textarea>

  <!-- honeypot — bots fill it; humans don't see it -->
  <input type="text" name="_hp" tabindex="-1" autocomplete="off"
         style="position:absolute; left:-9999px; height:0;">

  <div class="cf-turnstile" data-sitekey="<%= ENV['TURNSTILE_SITEKEY'] %>"></div>
  <script src="https://challenges.cloudflare.com/turnstile/v0/api.js" async defer></script>

  <button type="submit">Request a tour</button>
</form>
```

Styling: operator-branded via existing `operator_branding` helper / CSS variables so it visually fits inside Untethered's site (and others). Single-column, clean, no JS framework dependency.

## Test plan (TDD order)

**Unit / model:**
- `Activity::KINDS` includes `:tour_request`
- `Activity.log(kind: :tour_request, ...)` creates a row with proper payload
- `ActivityTimelineHelper` groups `:tour_request` under Tours

**Service:**
- `Turnstile::Verifier` — happy path stubbed Faraday response; failure path; test-env short-circuit returns `success: true`

**Notifiable:**
- `Notifiable::TourRequestAlert#recipients` — returns operator admins + location managers, no duplicates, scoped to the right operator
- `should_send_notification?` true only for kind `tour_request`
- email is sent to each recipient

**Controller (request specs):**
- GET `/embed/tour_request/:subdomain` returns 200, renders form, allows framing
- GET with disabled widget returns 404
- POST happy path creates User + Activity, enqueues notification, redirects to thank_you
- POST with honeypot filled → 200 but no DB write (assert `Activity.count` unchanged)
- POST with bad Turnstile → 422, no DB write
- POST exceeding rate limit → 429 (sixth request in a minute from same IP)
- POST with existing User (same email + operator) → finds, doesn't duplicate, still logs Activity
- POST with cross-tenant subdomain mismatch → 404 (security)

**Settings request specs:**
- GET `/operator/settings/tour_widget` as admin → 200
- GET as member → 302 / redirect
- PATCH update with valid params → persists, flashes success
- Snippet output contains operator subdomain + selected location

**End-to-end smoke (manual, after build):**
- Open `https://localhost:3000/operator/settings/tour_widget` as Untethered admin, copy iframe snippet
- Paste into a local test HTML file, open in browser, submit
- Verify User + Activity created in Rails console
- Verify email landed in MailCatcher / dev mailer
- Verify Person timeline shows the request under Tours tab

## Migration order

This is one PR. Migrations:
1. `AddTourWidgetFieldsToOperators` — three columns, all nullable defaults so backfill is unnecessary.
2. `has_rich_text :tour_widget_intro_html` adds `action_text_rich_texts` rows on save — no schema migration needed beyond the existing Action Text table.

No data backfill required.

## ENV / config additions

- `TURNSTILE_SITEKEY` — public, embedded in form HTML
- `TURNSTILE_SECRET` — server-side, used by `Turnstile::Verifier`

Document in `.env.example` + onboarding docs. Tests + dev short-circuit when `TURNSTILE_SECRET` is blank.

## File-level scope estimate

| File | Type | LOC |
|---|---|---|
| `app/controllers/embed/tour_requests_controller.rb` | new | ~110 |
| `app/controllers/operator/settings_controller.rb` | modify (2 actions) | ~40 |
| `app/views/embed/tour_requests/show.html.erb` | new | ~20 |
| `app/views/embed/tour_requests/_form.html.erb` | new | ~50 |
| `app/views/embed/tour_requests/thank_you.html.erb` | new | ~15 |
| `app/views/operator/settings/tour_widget.html.erb` | new | ~90 |
| `app/services/turnstile/verifier.rb` | new | ~30 |
| `app/adapters/notifiable/tour_request_alert.rb` | new | ~45 |
| `app/mailers/tour_request_mailer.rb` + view | new | ~40 |
| `app/models/activity.rb` | modify (KINDS) | ~2 |
| `app/helpers/activity_timeline_helper.rb` | modify | ~2 |
| `config/routes.rb` | modify | ~10 |
| `config/initializers/rack_attack.rb` | new | ~20 |
| `db/migrate/<ts>_add_tour_widget_fields_to_operators.rb` | new | ~15 |
| Specs (request + model + adapter + service) | new | ~250 |

**Total ~740 LOC.** Slightly over the 600 target — within tolerance. The notification mailer + adapter are the addition over the original memory's scope.

## Security checklist (security skill)

- ✅ Public endpoint: CSRF skipped only on `/embed/*`, not elsewhere
- ✅ Mass assignment: explicit `params.permit(:name, :email, :phone, :message, :location_id)` — no permit!
- ✅ Tenant isolation: subdomain → operator lookup, `acts_as_tenant` scopes all writes
- ✅ Open redirect: `tour_widget_thank_you_url` validated as absolute URL with `http(s)` scheme on save
- ✅ XSS: `tour_widget_intro_html` rendered via Action Text (sanitized by default)
- ✅ Rate limit: Rack::Attack 5/min/IP on `/embed/*`
- ✅ Bot defense: honeypot + Turnstile
- ✅ Frame embedding: `X-Frame-Options: ALLOWALL` scoped to `/embed/*` only via `after_action`, not in global config
- ✅ Email enumeration: find-or-create returns the same response shape whether email exists or not (no "user already exists" leak)
- ✅ Honeybadger.notify on Turnstile network failures (don't silently fail open)

## Open items / followups (not in this PR)

- Phase 2 JS widget — `<script src="…/widget.js">` for operators who want custom CSS hooks
- Per-operator Turnstile sitekey override
- Tour-request analytics on the operator dashboard (count/week, conversion to membership)
- Campaign Attribution chip — drops in once Lead deprecation PR 4 lands
