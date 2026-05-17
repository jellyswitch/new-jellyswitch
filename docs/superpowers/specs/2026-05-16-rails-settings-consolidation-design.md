# Design: Rails Settings Consolidation

**Date:** 2026-05-16
**Status:** Approved (design phase) — pending implementation plan
**Sub-project:** A (of A–E in the broader app-setup work)
**Branch context:** `claude/zealous-montalcini-af4f45` (worktree of `main`)

## Background

Operator admins today have to bounce between three scattered admin pages to fully configure a coworking space, and a fourth set of settings (Stripe Connect) is only reachable via a modal launched from the Modules page:

| Page | Route | Editable? | Content |
|---|---|---|---|
| Settings | `/operator/operators/:id/edit` | Yes | Operator-edit form |
| Customization | `/customization` | Partially | Nav-hub for Modules / Global / Notifications / Location + inline Mailchimp form |
| App Config | `/app_configs` | Read-only | iOS/Android push cert status, logo, promo text |
| Stripe Connect | modal from `/modules` | OAuth | Connect/reconnect Stripe account |

Mobile (`src/screens/admin/AdminSettingsScreen.js`) is already a single consolidated screen. Web is fragmented. This design brings web up to parity by consolidating into one `/operator/settings/{tab}` surface.

Yesterday's full inventory of this and adjacent setup-flow problems is captured in `~/.claude/projects/-Users-DavidOrr-Downloads-new-jellyswitch/memory/project_setup_flow_inventory.md` — read that for fuller context.

## Goals

1. One admin entry point for all operator-managed configuration.
2. Per-tab strong-params boundaries so saving one section can't accidentally mutate another.
3. Establish a project-wide `dollars` convention for money fields (UI = dollars w/ cent precision; DB stays in cents).
4. No model schema changes. No new KISI/Stripe integration code. Reuse existing interactors and the existing OAuth modal.
5. Push cert / Firebase / APNs management stays admin-only (out of operator-facing Settings) but does not get deleted — it stays at `/app_configs` gated behind admin auth.

## Non-Goals

- Mobile parity changes (`AdminSettingsScreen.js`) — sub-project 2 in the inventory.
- Adding a Stripe Connect step to the onboarding wizard — sub-project B.
- Smart signup-time location selection (geolocation, auto-pick closest) — sub-project C.
- Mobile UI polish, Maestro regression, TestFlight — sub-projects D & E.
- Migrating any `_in_cents` columns. Schema unchanged.
- Touching UI of every existing money field — only `day_pass_cost` (the field in scope here) gets a UI update in this PR. Concern is declared on other models so the convention is consistent everywhere, but their forms stay untouched.

## Architecture

### Routes

```ruby
namespace :operator do
  resource :settings, only: [] do
    member do
      get   :branding
      patch :update_branding
      get   :payments                   # no patch — OAuth handles
      get   :doors
      patch :update_doors
      post  :import_doors               # KISI door import
      get   :hours_and_address
      patch :update_hours_and_address
      get   :wifi_and_pixels
      patch :update_wifi_and_pixels
      get   :notifications
      patch :update_notifications
      get   :modules
      patch :update_modules
      get   :policies
      patch :update_policies
    end
  end
end

# Legacy redirects
get '/customization',               to: 'operator/settings#legacy_redirect'
get '/operator/operators/:id/edit', to: 'operator/settings#legacy_redirect'

# Bare /operator/settings → 302 to default tab
get '/operator/settings', to: 'operator/settings#index'  # redirects to branding
```

### Controller

One controller: `Operator::SettingsController`.

- 8 tab GET actions: `branding`, `payments`, `doors`, `hours_and_address`, `wifi_and_pixels`, `notifications`, `modules`, `policies`
- 7 update actions: `update_branding`, `update_doors`, `update_hours_and_address`, `update_wifi_and_pixels`, `update_notifications`, `update_modules`, `update_policies`
- 1 import action: `import_doors` (calls `Onboarding::GetKisiDoors`)
- 1 helper action: `legacy_redirect` (301 to `/operator/settings/branding`)
- 1 default action: `index` (302 to `/operator/settings/branding`)

Each `update_*` has its own private `*_params` method permitting only the fields that tab owns. No shared params method.

### Views

- `app/views/operator/settings/_tab_layout.html.erb` — shared left-rail nav + content yield
- `app/views/operator/settings/branding.html.erb`
- `app/views/operator/settings/payments.html.erb`
- `app/views/operator/settings/doors.html.erb`
- `app/views/operator/settings/hours_and_address.html.erb`
- `app/views/operator/settings/wifi_and_pixels.html.erb`
- `app/views/operator/settings/notifications.html.erb`
- `app/views/operator/settings/modules.html.erb`
- `app/views/operator/settings/policies.html.erb`

Tab views are wrapped by `_tab_layout.html.erb` (rendered via `render layout:` or `content_for :tab_content`).

### Scope resolution

- Operator-scope tabs (Branding, Notifications, Modules, Policies): use `current_operator`.
- Location-scope tabs (Hours & Address, WiFi & Pixels): use `current_user.current_location`. If `current_operator.locations.count > 1`, show an in-tab `<select>` location switcher that posts a session update and re-renders the tab. The switcher is local to that tab — does NOT change `current_user.current_location` globally.
- Doors tab: hybrid. Operator-level KISI key + per-location overrides + per-location door list.
- Payments tab: location-scope with the same in-tab switcher.

## Tab content

### 1. Branding & Content (Operator)

| Field | Type | Storage |
|---|---|---|
| Logo | image upload | `Operator#logo_image` (Active Storage) |
| Snippet | string | `operator.snippet` |
| Membership text | text | `operator.membership_text` |
| Terms of service | file | `operator.terms_of_service` (Active Storage) |
| Google reviews URL | string | `operator.google_reviews_url` |

### 2. Payments (Location)

No editable form. Status panel + OAuth handoff.

**Connected state:**
- Green dot + "Stripe Connected"
- Last chars of `stripe_user_id` (`acct_•••••XYZ`)
- Last chars of `stripe_publishable_key` (`pk_live_•••••AB12`)
- `[Reconnect Stripe Account]` button — opens existing OAuth modal

**Disconnected state:**
- Gray dot + "Stripe Not Connected"
- Explanatory copy
- `[Connect Stripe Account]` button — opens existing OAuth modal

**Mechanics:**
- Status check: `location.stripe_user_id.present? && location.stripe_access_token.present?`
- Modal: reuse `app/views/shared/_stripe_connect_modal.html.erb` unchanged
- OAuth callback uses the existing `Operators::FinishStripeConnect` interactor — unchanged. Only change: redirect target after success is `/operator/settings/payments` (instead of `/customization`).
- No Disconnect button. Revocation rare and orphans subscriptions. If needed, do it via Rails console.

### 3. Doors (Operator-level with per-location override)

**Sections within the tab:**

1. **KISI API key (operator-level)** — single masked input. Save writes to `operator.kisi_api_key`. Existing `Operator#after_save` cascade fills `Location#kisi_api_key` for any location where it's currently nil. Cascade behavior is unchanged.

2. **Per-location overrides** — collapsed list of locations. Each row shows:
   - Location name
   - Status: "uses operator default" (if `location.kisi_api_key.nil?`) OR masked override key (`kisi_•••• 9c3f`)
   - `[Edit]` button → inline Turbo Frame for editing/clearing that location's `kisi_api_key`
   - Clearing the field puts the location back on operator-default.
   - The "uses operator default" badge checks `location.kisi_api_key.nil?` specifically, NOT equality with operator's key — so a stale override won't mislead.

3. **Door list + import**
   - "Import doors from KISI" button with location selector (auto-selects only location if single-location)
   - Posts to `Operator::SettingsController#import_doors` which calls existing `Onboarding::GetKisiDoors.run(location: …)` interactor
   - Door list rendered via Turbo Frame `id="doors_list"` with `src="<%= doors_path(location_id: …) %>"`
   - `Operator::DoorsController#index` view gets its content wrapped in `<%= turbo_frame_tag "doors_list" do %>` so it works both standalone (existing usage) and embedded.
   - Door create/edit/destroy/archive continue to hit existing `Operator::DoorsController` routes. Their redirects refresh the Turbo Frame in place.

### 4. Hours & Address (Location, with in-tab switcher)

| Field | Type | Storage |
|---|---|---|
| Name | string | `location.name` |
| Building address, city, state, zip | strings | `location.{building_address,city,state,zip}` |
| Latitude, longitude | decimal | `location.{latitude,longitude}` (auto-geocoded on save — implementation note below) |
| Time zone | select (Rails `time_zone_select`) | `location.time_zone` |
| Working day start, end | time pickers | `location.{working_day_start,working_day_end}` |
| Open Sunday–Saturday | 7 checkboxes | `location.open_*` |
| Building access instructions | textarea | `location.building_access_instructions` |
| Contact name, email, phone | strings | `location.{contact_name,contact_email,contact_phone}` |

**Geocoding note:** `latitude`/`longitude` columns already exist on Location (Section 2 schema check). This PR does NOT add `geocoder` gem or wire auto-geocoding on save — that work belongs to sub-project C (smart signup geolocation). For now, those fields are exposed as plain numeric inputs (operator can paste coordinates manually). Visible but optional. Field-level note in the form: "Auto-population coming soon."

### 5. WiFi & Pixels (Location, with in-tab switcher)

| Field | Type | Storage |
|---|---|---|
| WiFi network name | string | `location.wifi_name` |
| WiFi password | string | `location.wifi_password` |
| Tracking pixels | TBD | needs grep at plan stage — likely on Operator (Facebook Pixel, GA) |

**Open item for plan stage:** identify where tracking pixel fields live today (Operator vs Location vs elsewhere). The inventory mentions "tracking pixels" on the location edit form but doesn't name the columns. Plan task: `rg -i "pixel|fbq|gtag" app/models app/views/operator/locations` and resolve.

### 6. Notifications (Operator)

- Notification email toggles (10 booleans on Operator):
  - `email_enabled`
  - `reservation_notifications`
  - `membership_notifications`
  - `signup_notifications`
  - `day_pass_notifications`
  - `member_feedback_notifications`
  - `checkin_notifications`
  - `refund_notifications`
  - `post_notifications`
  - `paid_room_reservation_notifications`
- `sender_email` (string) — outgoing "From:" address
- Mailchimp section (moved from `/customization`):
  - `mailchimp_api_key`
  - `mailchimp_audience_id`

### 7. Modules (Operator)

9 boolean toggles for product modules on Operator:
- `announcements_enabled`
- `events_enabled`
- `door_integration_enabled`
- `rooms_enabled`
- `offices_enabled`
- `bulletin_board_enabled`
- `credits_enabled` — show warning underneath: "Credits feature is currently dormant; toggling on may not behave as expected." (Per `project_credits_feature_dormant` memory.)
- `childcare_enabled`
- `crm_enabled`

### 8. Policies (Operator)

| Field | UI | Storage | Notes |
|---|---|---|---|
| Day pass price | `$` input, `step: "0.01"`, prepended `$` | `day_pass_cost_in_cents` via `dollars :day_pass_cost` virtual attr | Per "Money in UI = dollars" rule |
| Refund fee % | number input, 0–100 | `refund_fee_percent` | Integer percent — not money |
| Cancellation window | number, hours | `cancellation_window_hours` | |
| Renewal reminder | number, days before renewal | `renewal_reminder_days` | |
| `approval_required` | checkbox | bool | |
| `checkin_required` | checkbox | bool | |

## Money / dollars convention

### `HasDollars` concern

New file: `app/models/concerns/has_dollars.rb`:

```ruby
module HasDollars
  extend ActiveSupport::Concern

  class_methods do
    def dollars(*names)
      names.each do |name|
        cents_attr = :"#{name}_in_cents"

        define_method(name) do
          cents = read_attribute(cents_attr)
          cents.nil? ? nil : cents / 100.0
        end

        define_method("#{name}=") do |value|
          write_attribute(cents_attr, value.blank? ? nil : (BigDecimal(value.to_s) * 100).to_i)
        end
      end
    end
  end
end
```

### Adoption in this PR

```ruby
# app/models/operator.rb
include HasDollars
dollars :day_pass_cost

# app/models/location.rb
include HasDollars
dollars :hourly_rate, :credit_cost, :childcare_reservation_cost
```

The `Location` declarations add the readers/writers but their UIs are NOT updated in this PR. Convention is established for the next time those forms are touched.

### Form input pattern

```erb
<%= f.input :day_pass_cost,
            as: :decimal,
            input_html: { step: "0.01", min: 0, value: f.object.day_pass_cost },
            prepend: "$" %>
```

### Strong params

Permit the virtual attribute, not the cents column:

```ruby
def policies_params
  params.require(:operator).permit(:day_pass_cost, :refund_fee_percent, :cancellation_window_hours, :renewal_reminder_days, :approval_required, :checkin_required)
end
```

### Display

Use `number_to_currency(operator.day_pass_cost_in_cents.to_d / 100)` → `$25.00`.

**Audit task at plan stage:** grep for direct rendering of `day_pass_cost_in_cents` across views, fix any that show raw cents.

## Migration / deprecation

### Redirects

| Old URL | Status | Target |
|---|---|---|
| `/operator/operators/:id/edit` | 301 | `/operator/settings/branding` |
| `/customization` | 301 | `/operator/settings/branding` |
| `/app_configs` | unchanged | stays, behind admin-only auth |

Redirect implementation (small action on `Operator::SettingsController`):

```ruby
def legacy_redirect
  redirect_to operator_settings_branding_path, status: :moved_permanently
end
```

### Deletions (in this PR)

- `app/views/operator/operators/edit.html.erb`
- `app/views/operator/landing/customization.html.erb`
- `Operator::OperatorsController#edit` and `#update` (params handling moves to the matching `update_*` tab actions)
- `LandingController#customization`

Justification: this is a private operator-admin app. There are no inbound external deep links. The 301s cover operator bookmarks. The views and actions have no other reason to exist after consolidation.

### `/app_configs` gating

Add `before_action :require_super_admin` (or whatever the existing super-admin check is named — verify at plan stage; likely `current_user.admin?` or a Pundit policy) on `Operator::AppConfigsController`. Operator nav loses its "App Configs" link.

## Nav placement

- Operator nav gains a top-level **Settings** entry (icon: gear).
- Operator nav loses: "Customization", "App Configs".
- "Settings" → `/operator/settings` → 302 to `/operator/settings/branding`.

## Testing

Following existing Minitest + RSpec patterns; CI runs Minitest unit → RSpec → Minitest system in sequence (per `reference_ci_three_jobs` memory).

### Model unit test

`test/models/concerns/has_dollars_test.rb`:
- Reads dollars from cents column
- Writes dollars to cents column (handles `"40.99"` → `4099`)
- Blank input clears the cents column to nil
- Works when applied to a model with `day_pass_cost`

### Request specs

`spec/requests/operator/settings/` (RSpec, one file per tab + cross-cutting):

For each tab:
- `GET` renders the tab without error
- `PATCH update_*` saves with valid params → 302 redirect + flash notice
- `PATCH update_*` returns 422 with invalid params (where applicable)
- Params NOT in the tab's whitelist are silently dropped (regression check — assert via DB read that a different column didn't change)

Doors tab additions:
- `POST import_doors` calls `Onboarding::GetKisiDoors.run` with the right location (stubbed), re-renders the Turbo Frame

Payments tab:
- `GET payments` when `location.stripe_user_id.present?` → renders Connected panel
- `GET payments` when `nil` → renders Not Connected panel
- No PATCH spec; OAuth flow tested elsewhere

Cross-cutting:
- `GET /customization` → 301 → `/operator/settings/branding`
- `GET /operator/operators/:id/edit` → 301 → `/operator/settings/branding`
- `GET /operator/settings` → 302 → `/operator/settings/branding`
- `GET /app_configs` as non-admin → 403 (or redirect)

### System test

`test/system/operator/settings_navigation_test.rb` (Minitest system, Capybara):
- Log in as operator → visit `/operator/settings` → land on Branding tab
- Tab through to Doors, Notifications, back — no JS errors
- Edit a Branding field → Save → reload → field persists

### Manual verification before declaring done

Per `verification-before-completion` rule:
- `bin/rails test` (Minitest unit + system) passes green
- `bundle exec rspec spec/requests/operator/settings` passes green
- Boot locally, click through all 8 tabs, save in each → no console errors, DB values actually changed

## Open items to resolve at plan stage

1. **Tracking pixels location** — grep for where they live; fold into WiFi & Pixels tab.
2. **Super-admin authentication helper name** — find existing pattern, reuse for `/app_configs` gating.
3. **Audit existing renderers of `day_pass_cost_in_cents`** — `rg "day_pass_cost_in_cents" app/views` and fix any that show raw cents.
4. **Default operator nav file** — identify the partial to edit when adding "Settings" + removing "Customization"/"App Configs". Likely `app/views/shared/_operator_nav.html.erb` or similar.
5. **`Operator::OperatorsController#update` callers** — grep to confirm nothing else hits it before deleting.
6. **simple_form vs vanilla form_with** — confirm which one the app uses (`Gemfile` check) so the form input pattern matches.
7. **Modules-page Stripe modal trigger** — `app/views/operator/modules/index.html.erb` currently has the Connect Stripe entry point. After this consolidation, decide: remove that trigger (single entry via Settings tab) or keep both. Default recommendation: remove, since the goal is consolidation.

These don't block the design; they're concrete tasks the implementation plan will resolve.
