# Tour Request Widget Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Jellyswitch-hosted, embeddable tour-request form (iframe-primary, HTML-snippet secondary) that captures `User + Activity(:tour_request)`, notifies operator admins + location managers (push + email), and is spam-hardened with honeypot + Rack::Attack + Cloudflare Turnstile.

**Architecture:** New public namespace `Embed::TourRequestsController` (CSRF-skipped, framing allowed, CORS open on POST). Strictly additive to existing Person + Activity system — no `Lead` rows. Operator-side snippet generator under `/operator/settings/tour_widget`. Push fan-out via existing `Notifiable` adapter pattern; email via new `TourRequestMailer`.

**Tech Stack:** Rails 8.1, Minitest + fixtures (`test/`), `acts_as_tenant`, Action Text (for `intro_html`), `rack-attack` (new gem), Cloudflare Turnstile (siteverify endpoint), Faraday (already present).

**Spec:** [docs/superpowers/specs/2026-05-17-tour-request-widget-design.md](../specs/2026-05-17-tour-request-widget-design.md)

---

## File map

**New files:**
- `db/migrate/<ts>_add_tour_widget_fields_to_operators.rb`
- `app/controllers/embed/tour_requests_controller.rb`
- `app/views/embed/tour_requests/show.html.erb`
- `app/views/embed/tour_requests/_form.html.erb`
- `app/views/embed/tour_requests/thank_you.html.erb`
- `app/views/operator/settings/tour_widget.html.erb`
- `app/services/turnstile/verifier.rb`
- `app/adapters/notifiable/tour_request_alert.rb`
- `app/mailers/tour_request_mailer.rb`
- `app/views/tour_request_mailer/new_request.html.erb`
- `app/views/tour_request_mailer/new_request.text.erb`
- `config/initializers/rack_attack.rb`
- `test/controllers/embed/tour_requests_controller_test.rb`
- `test/controllers/operator/settings_tour_widget_test.rb`
- `test/adapters/notifiable/tour_request_alert_test.rb`
- `test/services/turnstile/verifier_test.rb`
- `test/mailers/tour_request_mailer_test.rb`

**Modified files:**
- `app/models/operator.rb` (Action Text association, helper)
- `app/models/activity.rb` (add `:tour_request` to KINDS)
- `app/helpers/activity_timeline_helper.rb` (add to Tours bucket)
- `app/controllers/operator/settings_controller.rb` (add `tour_widget`, `update_tour_widget` actions)
- `app/views/operator/settings/_tab_layout.html.erb` (add tab entry)
- `config/routes.rb` (embed namespace + 2 settings routes)
- `Gemfile` + `Gemfile.lock` (`rack-attack`)
- `.env.example` (`TURNSTILE_SITEKEY`, `TURNSTILE_SECRET`)

---

## Task 1: Migration — add tour widget fields to operators

**Files:**
- Create: `db/migrate/<timestamp>_add_tour_widget_fields_to_operators.rb`

- [ ] **Step 1: Generate migration**

Run: `bin/rails g migration AddTourWidgetFieldsToOperators tour_widget_enabled:boolean tour_widget_thank_you_url:string`

- [ ] **Step 2: Edit generated migration to set safe defaults**

```ruby
class AddTourWidgetFieldsToOperators < ActiveRecord::Migration[8.1]
  def change
    add_column :operators, :tour_widget_enabled,       :boolean, default: false, null: false
    add_column :operators, :tour_widget_thank_you_url, :string
  end
end
```

Note: `tour_widget_intro_html` is Action Text, stored in `action_text_rich_texts`, no schema column needed.

- [ ] **Step 3: Run migration**

Run: `bin/rails db:migrate db:test:prepare`
Expected: schema.rb updates with new columns; no errors.

- [ ] **Step 4: Commit**

```bash
git add db/migrate db/schema.rb
git commit -m "Add tour_widget_enabled + tour_widget_thank_you_url to operators"
```

---

## Task 2: Add `:tour_request` Activity kind + Tours group

**Files:**
- Modify: `app/models/activity.rb` (KINDS array)
- Modify: `app/helpers/activity_timeline_helper.rb` (KIND_GROUPS)
- Test: `test/models/activity_test.rb` (new test)

- [ ] **Step 1: Write failing test for Activity kind**

Add to `test/models/activity_test.rb` (create the file if it doesn't exist — start with `require 'test_helper'` + `class ActivityTest < ActiveSupport::TestCase`):

```ruby
test "tour_request is a valid Activity kind" do
  user = users(:cowork_tahoe_member)
  operator = user.operator
  activity = Activity.new(user: user, operator: operator, kind: :tour_request, occurred_at: Time.current, payload: {})
  assert activity.valid?, activity.errors.full_messages.inspect
end
```

- [ ] **Step 2: Run test, confirm it fails**

Run: `bin/rails test test/models/activity_test.rb -n test_tour_request_is_a_valid_Activity_kind`
Expected: FAIL — `kind` not in inclusion list.

- [ ] **Step 3: Add `tour_request` to `Activity::KINDS`**

Edit `app/models/activity.rb`:

```ruby
KINDS = %w[
  signup
  tour
  tour_request
  checkin
  door_punch
  reservation
  day_pass
  subscription_started
  subscription_ended
  payment_succeeded
  payment_failed
  note
  email_sent
  email_opened
  email_clicked
  email_replied
].freeze
```

- [ ] **Step 4: Run test, confirm it passes**

Run: `bin/rails test test/models/activity_test.rb -n test_tour_request_is_a_valid_Activity_kind`
Expected: PASS.

- [ ] **Step 5: Add `:tour_request` to Tours bucket in ActivityTimelineHelper**

First find the Tours bucket:

Run: `grep -n "tour\|KIND_GROUPS" app/helpers/activity_timeline_helper.rb`

Edit `app/helpers/activity_timeline_helper.rb` to include `tour_request` next to `tour` in the appropriate group (likely `:tours`). Example expected shape:

```ruby
KIND_GROUPS = {
  tours: %w[tour tour_request],
  # ...other groups unchanged
}
```

- [ ] **Step 6: Commit**

```bash
git add app/models/activity.rb app/helpers/activity_timeline_helper.rb test/models/activity_test.rb
git commit -m "Add :tour_request Activity kind; group with Tours in timeline"
```

---

## Task 3: Add rack-attack gem + initializer

**Files:**
- Modify: `Gemfile`
- Create: `config/initializers/rack_attack.rb`
- Test: `test/controllers/embed/tour_requests_controller_test.rb` (the rate-limit test comes later in Task 7 — for now just stand up the initializer)

- [ ] **Step 1: Add gem to Gemfile**

Add this line in the main group:

```ruby
gem "rack-attack", "~> 6.7"
```

- [ ] **Step 2: Install**

Run: `bundle install`
Expected: rack-attack added to Gemfile.lock.

- [ ] **Step 3: Create initializer**

Create `config/initializers/rack_attack.rb`:

```ruby
class Rack::Attack
  ### Throttle /embed/* POSTs to 5/minute per IP ###
  throttle("embed/ip", limit: 5, period: 1.minute) do |req|
    req.ip if req.post? && req.path.start_with?("/embed/")
  end

  ### Custom response for throttled requests ###
  self.throttled_responder = lambda do |env|
    [429, { "Content-Type" => "text/plain" }, ["Too many requests. Please wait a minute and try again."]]
  end
end

# Enable in production + test (so we can write a test for it).
# In dev, leave off — local testing of the form shouldn't trigger it.
Rails.application.config.middleware.use Rack::Attack unless Rails.env.development?
```

- [ ] **Step 4: Enable cache store for Rack::Attack in tests**

Run: `grep -n "config.cache_store" config/environments/test.rb`

If it's `:null_store` (default), Rack::Attack throttle won't work in tests because there's no counter. Edit `config/environments/test.rb` to use `:memory_store`:

```ruby
config.cache_store = :memory_store
```

(Skip this if it's already memory_store.)

- [ ] **Step 5: Run full test suite quickly to confirm nothing broke**

Run: `bin/rails test test/models -q`
Expected: all pass; rack-attack doesn't fire for non-/embed routes.

- [ ] **Step 6: Commit**

```bash
git add Gemfile Gemfile.lock config/initializers/rack_attack.rb config/environments/test.rb
git commit -m "Add rack-attack + throttle /embed/* to 5/min per IP"
```

---

## Task 4: Turnstile verifier service (TDD)

**Files:**
- Create: `app/services/turnstile/verifier.rb`
- Test: `test/services/turnstile/verifier_test.rb`

- [ ] **Step 1: Write failing test — short-circuit when secret blank**

Create `test/services/turnstile/verifier_test.rb`:

```ruby
require 'test_helper'

class Turnstile::VerifierTest < ActiveSupport::TestCase
  test "short-circuits to success when TURNSTILE_SECRET is blank" do
    ENV.stub :[], nil do
      result = Turnstile::Verifier.call(token: "anything", remote_ip: "127.0.0.1")
      assert result.success?
    end
  end

  test "returns success when Cloudflare reports valid token" do
    ENV.stub :[], "test-secret" do
      stub_response = OpenStruct.new(body: { "success" => true }.to_json, success?: true)
      Faraday.stub :post, stub_response do
        result = Turnstile::Verifier.call(token: "good-token", remote_ip: "1.2.3.4")
        assert result.success?
      end
    end
  end

  test "returns failure when Cloudflare reports invalid token" do
    ENV.stub :[], "test-secret" do
      stub_response = OpenStruct.new(body: { "success" => false }.to_json, success?: true)
      Faraday.stub :post, stub_response do
        result = Turnstile::Verifier.call(token: "bad-token", remote_ip: "1.2.3.4")
        refute result.success?
      end
    end
  end

  test "fails closed on network error and reports to Honeybadger" do
    ENV.stub :[], "test-secret" do
      Honeybadger.expects(:notify).at_least_once
      Faraday.stubs(:post).raises(Faraday::ConnectionFailed.new("boom"))
      result = Turnstile::Verifier.call(token: "x", remote_ip: "1.2.3.4")
      refute result.success?
    end
  end
end
```

(Note: this codebase mixes `stub` and `mocha`-style `expects`/`stubs` — `point_of_contact_alert_test` and `weekly_update_test` use mocha. Use mocha here too for consistency: `Honeybadger.expects(:notify)`.)

- [ ] **Step 2: Run tests, confirm all 4 fail**

Run: `bin/rails test test/services/turnstile/verifier_test.rb -v`
Expected: FAIL — `Turnstile::Verifier` not defined.

- [ ] **Step 3: Implement the verifier**

Create `app/services/turnstile/verifier.rb`:

```ruby
module Turnstile
  class Verifier
    Result = Struct.new(:success?, :error_codes, keyword_init: true)

    VERIFY_URL = "https://challenges.cloudflare.com/turnstile/v0/siteverify".freeze

    def self.call(token:, remote_ip:)
      new(token, remote_ip).call
    end

    def initialize(token, remote_ip)
      @token = token
      @remote_ip = remote_ip
    end

    def call
      return Result.new(success?: true, error_codes: []) if ENV["TURNSTILE_SECRET"].blank?

      response = Faraday.post(VERIFY_URL, {
        secret: ENV["TURNSTILE_SECRET"],
        response: @token,
        remoteip: @remote_ip,
      })

      body = JSON.parse(response.body)
      Result.new(success?: body["success"] == true, error_codes: Array(body["error-codes"]))
    rescue Faraday::Error, JSON::ParserError => e
      Honeybadger.notify(e, context: { remote_ip: @remote_ip })
      Result.new(success?: false, error_codes: ["network-error"])
    end
  end
end
```

- [ ] **Step 4: Run tests, confirm all 4 pass**

Run: `bin/rails test test/services/turnstile/verifier_test.rb -v`
Expected: 4 runs, 4 assertions, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add app/services/turnstile/verifier.rb test/services/turnstile/verifier_test.rb
git commit -m "Add Turnstile::Verifier service (siteverify wrapper, fail-closed)"
```

---

## Task 5: Operator helper methods for tour widget

**Files:**
- Modify: `app/models/operator.rb` (Action Text association + helper)
- Test: `test/models/operator_test.rb` (extend)

- [ ] **Step 1: Write failing test for `tour_widget_active?`**

Add to `test/models/operator_test.rb`:

```ruby
test "tour_widget_active? requires enabled flag and at least one visible location" do
  operator = operators(:cowork_tahoe)

  operator.update!(tour_widget_enabled: false)
  refute operator.tour_widget_active?

  operator.update!(tour_widget_enabled: true)
  assert operator.tour_widget_active?, "should be active with enabled + visible location"

  # If the operator has no visible locations, widget should be inactive.
  operator.locations.update_all(visible: false)
  refute operator.reload.tour_widget_active?
end
```

- [ ] **Step 2: Run test, confirm it fails**

Run: `bin/rails test test/models/operator_test.rb -n test_tour_widget_active?_requires_enabled_flag_and_at_least_one_visible_location`
Expected: FAIL — `NoMethodError: tour_widget_active?`.

- [ ] **Step 3: Add Action Text + helper to Operator**

Edit `app/models/operator.rb`. Near the top of the class (after existing associations), add:

```ruby
has_rich_text :tour_widget_intro_html
```

Then add the helper method (with other public methods):

```ruby
def tour_widget_active?
  tour_widget_enabled? && locations.where(visible: true).exists?
end
```

- [ ] **Step 4: Add open-redirect validation on thank_you URL**

In `app/models/operator.rb`, add:

```ruby
validates :tour_widget_thank_you_url,
          allow_blank: true,
          format: {
            with: %r{\Ahttps?://},
            message: "must start with http:// or https://"
          }
```

Add a test for this in `test/models/operator_test.rb`:

```ruby
test "tour_widget_thank_you_url rejects non-http schemes" do
  operator = operators(:cowork_tahoe)
  operator.tour_widget_thank_you_url = "javascript:alert(1)"
  refute operator.valid?
  assert_includes operator.errors[:tour_widget_thank_you_url].first, "http"
end

test "tour_widget_thank_you_url accepts https" do
  operator = operators(:cowork_tahoe)
  operator.tour_widget_thank_you_url = "https://example.com/thanks"
  assert operator.valid?
end
```

- [ ] **Step 5: Run all operator model tests**

Run: `bin/rails test test/models/operator_test.rb`
Expected: PASS, including the three new tests.

- [ ] **Step 6: Commit**

```bash
git add app/models/operator.rb test/models/operator_test.rb
git commit -m "Operator: tour_widget_active? helper, intro_html (Action Text), thank-you URL validation"
```

---

## Task 6: Routes for embed namespace + settings tab

**Files:**
- Modify: `config/routes.rb`

- [ ] **Step 1: Add embed routes (top-level, no subdomain constraint)**

Edit `config/routes.rb`. Near the top of `Rails.application.routes.draw do` (next to the existing global `/sendgrid/events` route), add:

```ruby
# Public embeddable tour-request widget (no auth, frame-able, CSRF-skipped).
namespace :embed do
  scope "tour_request/:subdomain" do
    get  "/",                       to: "tour_requests#show",      as: :tour_request
    get  "/locations/:location_id", to: "tour_requests#show",      as: :tour_request_for_location
    post "/",                       to: "tour_requests#create"
    get  "/thank_you",              to: "tour_requests#thank_you", as: :tour_request_thank_you
  end
end
```

- [ ] **Step 2: Add settings routes for the snippet generator page**

In `config/routes.rb`, find the `scope "/operator/settings"` block (around line 773) and add:

```ruby
get   "tour_widget",        to: "operator/settings#tour_widget",        as: :tour_widget
patch "update_tour_widget", to: "operator/settings#update_tour_widget", as: :update_tour_widget
```

- [ ] **Step 3: Verify routes load**

Run: `bin/rails routes | grep -E "embed|tour_widget"`
Expected: lists 4 embed routes + 2 settings routes.

- [ ] **Step 4: Commit**

```bash
git add config/routes.rb
git commit -m "Routes for /embed/tour_request/* and /operator/settings/tour_widget"
```

---

## Task 7: EmbedController GET — render form

**Files:**
- Create: `app/controllers/embed/tour_requests_controller.rb`
- Create: `app/views/embed/tour_requests/show.html.erb`
- Create: `app/views/embed/tour_requests/_form.html.erb`
- Test: `test/controllers/embed/tour_requests_controller_test.rb`

- [ ] **Step 1: Write failing test for GET happy path**

Create `test/controllers/embed/tour_requests_controller_test.rb`:

```ruby
require 'test_helper'

class Embed::TourRequestsControllerTest < ActionDispatch::IntegrationTest
  setup do
    setup_initial_user_fixtures
    @operator = operators(:cowork_tahoe)
    @operator.update!(tour_widget_enabled: true)
    @location = @operator.locations.first
    @location.update!(visible: true)
  end

  test "GET show renders form when widget enabled" do
    get embed_tour_request_path(subdomain: @operator.subdomain)
    assert_response :success
    assert_select "form[action=?][method=?]",
                  embed_tour_request_path(subdomain: @operator.subdomain), "post"
    assert_select "input[name=email]"
    assert_select "input[name=_hp]"
  end

  test "GET show 404s when widget disabled" do
    @operator.update!(tour_widget_enabled: false)
    get embed_tour_request_path(subdomain: @operator.subdomain)
    assert_response :not_found
  end

  test "GET show 404s when subdomain unknown" do
    get embed_tour_request_path(subdomain: "no-such-operator")
    assert_response :not_found
  end

  test "GET show with pinned location hides the picker and pre-selects" do
    get embed_tour_request_for_location_path(subdomain: @operator.subdomain, location_id: @location.id)
    assert_response :success
    assert_select "input[type=hidden][name=location_id][value=?]", @location.id.to_s
  end

  test "GET show sets X-Frame-Options ALLOWALL" do
    get embed_tour_request_path(subdomain: @operator.subdomain)
    assert_equal "ALLOWALL", response.headers["X-Frame-Options"]
  end
end
```

- [ ] **Step 2: Run, confirm all 5 fail**

Run: `bin/rails test test/controllers/embed/tour_requests_controller_test.rb -v`
Expected: FAIL — no controller / route doesn't resolve.

- [ ] **Step 3: Create the controller (GET only for now)**

Create `app/controllers/embed/tour_requests_controller.rb`:

```ruby
module Embed
  class TourRequestsController < ActionController::Base
    # Public endpoint — no app layout, no auth.
    layout "embed"

    skip_before_action :verify_authenticity_token, raise: false

    before_action :load_operator
    before_action :require_widget_active
    before_action :load_locations
    after_action  :allow_framing

    def show
      @pinned_location = @operator.locations.find_by(id: params[:location_id]) if params[:location_id]
      render :show
    end

    def thank_you
      render :thank_you
    end

    private

    def load_operator
      @operator = Operator.find_by(subdomain: params[:subdomain])
      head :not_found and return unless @operator
      ActsAsTenant.current_tenant = @operator
    end

    def require_widget_active
      head :not_found and return unless @operator.tour_widget_active?
    end

    def load_locations
      @locations = @operator.locations.where(visible: true).order(:name)
    end

    def allow_framing
      response.headers["X-Frame-Options"] = "ALLOWALL"
      response.headers.delete("Content-Security-Policy")
    end
  end
end
```

- [ ] **Step 4: Create minimal embed layout**

Create `app/views/layouts/embed.html.erb`:

```erb
<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Request a tour — <%= @operator.name %></title>
    <%= stylesheet_link_tag "embed", "data-turbo-track": "reload" %>
  </head>
  <body class="embed-tour-request">
    <%= yield %>
  </body>
</html>
```

For the asset pipeline: if Sprockets is in use, also create `app/assets/stylesheets/embed.css` with basic clean styling (~30 lines: form layout, button, font-stack). If Propshaft/no separate manifest is in use, inline the styles in the layout `<style>` block instead. Run `ls app/assets/stylesheets/` to check.

- [ ] **Step 5: Create the form partial**

Create `app/views/embed/tour_requests/_form.html.erb`:

```erb
<form action="<%= embed_tour_request_path(subdomain: @operator.subdomain) %>" method="post" class="tour-request-form">
  <% if @operator.tour_widget_intro_html.body.present? %>
    <div class="intro"><%= @operator.tour_widget_intro_html %></div>
  <% end %>

  <% if @pinned_location %>
    <input type="hidden" name="location_id" value="<%= @pinned_location.id %>">
  <% elsif @locations.size > 1 %>
    <label>
      Location
      <select name="location_id" required>
        <% @locations.each do |loc| %>
          <option value="<%= loc.id %>"><%= loc.name %></option>
        <% end %>
      </select>
    </label>
  <% elsif @locations.size == 1 %>
    <input type="hidden" name="location_id" value="<%= @locations.first.id %>">
  <% end %>

  <label>
    Your name
    <input type="text" name="name" required>
  </label>

  <label>
    Email
    <input type="email" name="email" required>
  </label>

  <label>
    Phone (optional)
    <input type="tel" name="phone">
  </label>

  <label>
    What are you looking for?
    <textarea name="message" rows="4"></textarea>
  </label>

  <!-- Honeypot: bots fill it; humans don't see it. -->
  <div style="position:absolute; left:-9999px; height:0; overflow:hidden;" aria-hidden="true">
    <label>Leave this empty: <input type="text" name="_hp" tabindex="-1" autocomplete="off"></label>
  </div>

  <% if ENV["TURNSTILE_SITEKEY"].present? %>
    <div class="cf-turnstile" data-sitekey="<%= ENV["TURNSTILE_SITEKEY"] %>"></div>
    <script src="https://challenges.cloudflare.com/turnstile/v0/api.js" async defer></script>
  <% end %>

  <button type="submit">Request a tour</button>
</form>
```

- [ ] **Step 6: Create show view**

Create `app/views/embed/tour_requests/show.html.erb`:

```erb
<h1>Request a tour at <%= @operator.name %></h1>
<%= render "form" %>
```

Create `app/views/embed/tour_requests/thank_you.html.erb`:

```erb
<h1>Thanks!</h1>
<p>Your tour request has been received. The <%= @operator.name %> team will be in touch shortly.</p>
```

- [ ] **Step 7: Run the GET tests**

Run: `bin/rails test test/controllers/embed/tour_requests_controller_test.rb -v`
Expected: 5 runs, all assertions pass.

- [ ] **Step 8: Commit**

```bash
git add app/controllers/embed app/views/embed app/views/layouts/embed.html.erb app/assets/stylesheets/embed.css test/controllers/embed
git commit -m "Embed::TourRequestsController#show + form partial + thank_you"
```

---

## Task 8: EmbedController POST — happy path

**Files:**
- Modify: `app/controllers/embed/tour_requests_controller.rb` (add `create`)
- Test: `test/controllers/embed/tour_requests_controller_test.rb` (extend)

- [ ] **Step 1: Write failing test for happy-path POST**

Append to `test/controllers/embed/tour_requests_controller_test.rb`:

```ruby
test "POST create with valid params creates a new User and tour_request Activity" do
  assert_difference -> { User.count } => 1,
                    -> { Activity.where(kind: "tour_request").count } => 1 do
    post embed_tour_request_path(subdomain: @operator.subdomain), params: {
      name: "Alex Tour",
      email: "alex+tour@example.com",
      phone: "555-1212",
      message: "Interested in a hot desk",
      location_id: @location.id,
    }
  end

  user = User.find_by(email: "alex+tour@example.com")
  assert_equal "Alex Tour", user.name
  assert_equal @operator.id, user.operator_id
  assert_equal @location.id, user.original_location_id

  activity = Activity.where(kind: "tour_request").last
  assert_equal user.id, activity.user_id
  assert_equal @operator.id, activity.operator_id
  assert_equal @location.id, activity.subject_id
  assert_equal "Location", activity.subject_type
  assert_equal "Interested in a hot desk", activity.payload["message"]
  assert_equal "widget", activity.payload["source"]

  assert_redirected_to embed_tour_request_thank_you_path(subdomain: @operator.subdomain)
end

test "POST create with existing email reuses the User and still logs Activity" do
  existing = User.create!(
    email: "existing+tour@example.com", name: "Existing", operator: @operator,
    original_location_id: @location.id, admin_created: true, password: "tempPass1!",
  )

  assert_difference -> { User.count } => 0,
                    -> { Activity.where(kind: "tour_request", user: existing).count } => 1 do
    post embed_tour_request_path(subdomain: @operator.subdomain), params: {
      name: "Existing", email: "existing+tour@example.com", location_id: @location.id,
    }
  end
end

test "POST create redirects to operator-configured thank-you URL if set" do
  @operator.update!(tour_widget_thank_you_url: "https://example.com/thanks")
  post embed_tour_request_path(subdomain: @operator.subdomain), params: {
    name: "Bea", email: "bea@example.com", location_id: @location.id,
  }
  assert_redirected_to "https://example.com/thanks"
end

test "POST with missing email returns 422" do
  post embed_tour_request_path(subdomain: @operator.subdomain), params: {
    name: "No Email", location_id: @location.id,
  }
  assert_response :unprocessable_entity
end
```

- [ ] **Step 2: Run tests, confirm 4 new ones fail**

Run: `bin/rails test test/controllers/embed/tour_requests_controller_test.rb -v`
Expected: 4 fails (no create action defined yet).

- [ ] **Step 3: Add `create` action**

Add to `app/controllers/embed/tour_requests_controller.rb`:

```ruby
def create
  # Honeypot: silent drop if filled.
  return head(:ok) if params[:_hp].present?

  # Turnstile verification (short-circuits when secret unset, e.g. test/dev).
  turnstile = Turnstile::Verifier.call(
    token: params["cf-turnstile-response"],
    remote_ip: request.remote_ip,
  )
  unless turnstile.success?
    flash.now[:error] = "Please retry the captcha."
    @pinned_location = @operator.locations.find_by(id: params[:location_id])
    return render(:show, status: :unprocessable_entity)
  end

  permitted = params.permit(:name, :email, :phone, :message, :location_id)
  location = @operator.locations.find_by(id: permitted[:location_id])

  if permitted[:email].blank? || permitted[:name].blank?
    flash.now[:error] = "Name and email are required."
    @pinned_location = location
    return render(:show, status: :unprocessable_entity)
  end

  user = User.find_or_initialize_by(email: permitted[:email].downcase.strip, operator: @operator)
  if user.new_record?
    user.name = permitted[:name]
    user.original_location_id = location&.id
    user.admin_created = true
    user.password = SecureRandom.hex(16)
    user.phone = permitted[:phone] if permitted[:phone].present?
  end
  user.save!

  activity = Activity.log(
    user: user,
    operator: @operator,
    kind: :tour_request,
    occurred_at: Time.current,
    subject: location,
    payload: {
      "message"  => permitted[:message],
      "source"   => "widget",
      "referrer" => request.referer,
    },
  )

  SendNotificationsJob.perform_later(activity, "TourRequestAlert")

  if @operator.tour_widget_thank_you_url.present?
    redirect_to @operator.tour_widget_thank_you_url, allow_other_host: true, status: :see_other
  else
    redirect_to embed_tour_request_thank_you_path(subdomain: @operator.subdomain), status: :see_other
  end
end
```

- [ ] **Step 4: Run tests, confirm all 4 new pass**

Run: `bin/rails test test/controllers/embed/tour_requests_controller_test.rb -v`
Expected: all tests pass (including existing 5 GET tests).

- [ ] **Step 5: Commit**

```bash
git add app/controllers/embed/tour_requests_controller.rb test/controllers/embed/tour_requests_controller_test.rb
git commit -m "Embed::TourRequestsController#create: User+Activity, honeypot, Turnstile, redirect"
```

---

## Task 9: Spam mitigation tests — honeypot, Turnstile failure, rate limit

**Files:**
- Modify: `test/controllers/embed/tour_requests_controller_test.rb`

- [ ] **Step 1: Add honeypot test**

```ruby
test "POST with honeypot filled silently returns 200 and writes nothing" do
  assert_no_difference -> { User.count } do
    assert_no_difference -> { Activity.count } do
      post embed_tour_request_path(subdomain: @operator.subdomain), params: {
        name: "Bot", email: "bot@spam.example", location_id: @location.id, _hp: "filled-by-bot",
      }
    end
  end
  assert_response :success
end
```

- [ ] **Step 2: Add Turnstile failure test**

```ruby
test "POST with failing Turnstile returns 422 and writes nothing" do
  ENV.stub :[], ->(k) { k == "TURNSTILE_SECRET" ? "stub-secret" : nil } do
    Turnstile::Verifier.stub :call, Turnstile::Verifier::Result.new(success?: false, error_codes: ["invalid"]) do
      assert_no_difference -> { Activity.count } do
        post embed_tour_request_path(subdomain: @operator.subdomain), params: {
          name: "Carl", email: "carl@example.com", location_id: @location.id, "cf-turnstile-response" => "bad",
        }
      end
      assert_response :unprocessable_entity
    end
  end
end
```

- [ ] **Step 3: Add rate-limit test**

```ruby
test "POST throttles after 5 requests per minute per IP" do
  Rails.cache.clear

  5.times do |i|
    post embed_tour_request_path(subdomain: @operator.subdomain), params: {
      name: "Rate#{i}", email: "rate#{i}@example.com", location_id: @location.id,
    }
  end
  # 6th request from the same IP within the window
  post embed_tour_request_path(subdomain: @operator.subdomain), params: {
    name: "Rate6", email: "rate6@example.com", location_id: @location.id,
  }
  assert_response :too_many_requests
end
```

- [ ] **Step 4: Run all controller tests**

Run: `bin/rails test test/controllers/embed/tour_requests_controller_test.rb -v`
Expected: All pass. If the rate-limit test fails because cache_store isn't memory_store in tests, fix Task 3 Step 4.

- [ ] **Step 5: Commit**

```bash
git add test/controllers/embed/tour_requests_controller_test.rb
git commit -m "Embed tour request: tests for honeypot, Turnstile failure, rate limit"
```

---

## Task 10: Notifiable::TourRequestAlert adapter (push fan-out)

**Files:**
- Create: `app/adapters/notifiable/tour_request_alert.rb`
- Test: `test/adapters/notifiable/tour_request_alert_test.rb`

- [ ] **Step 1: Write failing tests**

Create `test/adapters/notifiable/tour_request_alert_test.rb`:

```ruby
require 'test_helper'

class Notifiable::TourRequestAlertTest < ActiveSupport::TestCase
  setup do
    setup_initial_user_fixtures
    @operator = operators(:cowork_tahoe)
    @location = @operator.locations.first
    @admin    = users(:cowork_tahoe_admin)
    @gm       = User.create!(
      email: "gm+tour@example.com", name: "GM Test", operator: @operator,
      role: User::GENERAL_MANAGER, current_location_id: @location.id,
      original_location_id: @location.id, admin_created: true, password: "tempPass1!", phone: "555-0000",
    )
    @requester = User.create!(
      email: "req+tour@example.com", name: "Req Test", operator: @operator,
      original_location_id: @location.id, admin_created: true, password: "tempPass1!", phone: "555-0001",
    )
    @activity = Activity.create!(
      user: @requester, operator: @operator, kind: "tour_request",
      occurred_at: Time.current, subject: @location, payload: { "message" => "Curious about hot desks" },
    )
    @notifiable = Notifiable::TourRequestAlert.new(@activity)
  end

  test "recipients includes operator admins" do
    assert_includes @notifiable.send(:recipients), @admin
  end

  test "recipients includes general managers at the requested location" do
    assert_includes @notifiable.send(:recipients), @gm
  end

  test "recipients excludes managers at other locations" do
    other_location = @operator.locations.create!(name: "Other", visible: true, time_zone: "Pacific Time (US & Canada)")
    other_gm = User.create!(
      email: "other-gm@example.com", name: "Other GM", operator: @operator,
      role: User::GENERAL_MANAGER, current_location_id: other_location.id,
      original_location_id: other_location.id, admin_created: true, password: "tempPass1!", phone: "555-9999",
    )
    refute_includes @notifiable.send(:recipients), other_gm
  end

  test "recipients de-duplicates if a user is both admin and GM" do
    @admin.update!(role: User::GENERAL_MANAGER, current_location_id: @location.id)
    recipients = @notifiable.send(:recipients)
    assert_equal recipients.uniq, recipients
  end

  test "should_send_notification? true only for tour_request kind" do
    assert @notifiable.send(:should_send_notification?)
    other = Activity.create!(user: @requester, operator: @operator, kind: "signup", occurred_at: Time.current, payload: {})
    refute Notifiable::TourRequestAlert.new(other).send(:should_send_notification?)
  end

  test "message includes requester name and message preview" do
    msg = @notifiable.send(:message)
    assert_includes msg, "Req Test"
    assert_includes msg.downcase, "tour request"
  end
end
```

- [ ] **Step 2: Run, confirm fails**

Run: `bin/rails test test/adapters/notifiable/tour_request_alert_test.rb -v`
Expected: FAIL — `Notifiable::TourRequestAlert` not defined.

- [ ] **Step 3: Implement the adapter**

Create `app/adapters/notifiable/tour_request_alert.rb`:

```ruby
module Notifiable
  # Push (and via Task 11 also email) to operator admins + the
  # requested location's general/community managers when a new tour
  # request comes in via the embed widget. Subject is the Activity.
  class TourRequestAlert < Notifiable::Default
    def operator
      __getobj__.operator
    end

    def notify
      super
      send_email
    end

    private

    def create_feed_item
      # No-op — the Person's Activity timeline shows the request in context.
    end

    def deep_link_data
      { type: "user", resource_id: __getobj__.user_id, path: "/users/#{__getobj__.user_id}" }
    end

    def should_send_notification?
      __getobj__.kind.to_s == "tour_request"
    end

    def message
      activity = __getobj__
      person = activity.user
      preview = activity.payload["message"].to_s.truncate(40)
      preview.present? ? "New tour request: #{person&.name} — #{preview}" : "New tour request: #{person&.name}"
    end

    def recipients
      activity = __getobj__
      op = activity.operator
      location = activity.subject_type == "Location" ? activity.subject : nil

      admins = op.users.where(role: User::ADMIN)
      managers = if location
        op.users.where(
          role: [User::GENERAL_MANAGER, User::COMMUNITY_MANAGER],
          current_location_id: location.id,
        )
      else
        User.none
      end

      (admins.to_a + managers.to_a).uniq
    end

    def send_email
      return unless should_send_notification?
      recipients.each do |recipient|
        TourRequestMailer
          .with(recipient: recipient, activity: __getobj__)
          .new_request
          .deliver_later
      end
    end
  end
end
```

- [ ] **Step 4: Run tests, confirm all 6 pass**

Run: `bin/rails test test/adapters/notifiable/tour_request_alert_test.rb -v`
Expected: 6 runs, all pass (the email send will be a no-op stub for now since `TourRequestMailer` doesn't exist yet — guard with `defined?(TourRequestMailer)` if you hit a NameError). Actually — define a placeholder mailer to keep the adapter clean. Skip ahead to Task 11 if you hit `NameError: TourRequestMailer`.

If tests fail because `TourRequestMailer` is undefined, jump to Task 11, complete it, then return here.

- [ ] **Step 5: Commit**

```bash
git add app/adapters/notifiable/tour_request_alert.rb test/adapters/notifiable/tour_request_alert_test.rb
git commit -m "Notifiable::TourRequestAlert: push fan-out to admins + location managers"
```

---

## Task 11: TourRequestMailer (email path)

**Files:**
- Create: `app/mailers/tour_request_mailer.rb`
- Create: `app/views/tour_request_mailer/new_request.html.erb`
- Create: `app/views/tour_request_mailer/new_request.text.erb`
- Test: `test/mailers/tour_request_mailer_test.rb`

- [ ] **Step 1: Write failing test**

Create `test/mailers/tour_request_mailer_test.rb`:

```ruby
require 'test_helper'

class TourRequestMailerTest < ActionMailer::TestCase
  setup do
    setup_initial_user_fixtures
    @operator = operators(:cowork_tahoe)
    @location = @operator.locations.first
    @recipient = users(:cowork_tahoe_admin)
    @requester = User.create!(
      email: "req+mailer@example.com", name: "Req M", operator: @operator,
      original_location_id: @location.id, admin_created: true, password: "tempPass1!", phone: "555-0002",
    )
    @activity = Activity.create!(
      user: @requester, operator: @operator, kind: "tour_request",
      occurred_at: Time.current, subject: @location,
      payload: { "message" => "Looking for office space for 3" },
    )
  end

  test "new_request email has correct to/subject and body" do
    mail = TourRequestMailer.with(recipient: @recipient, activity: @activity).new_request

    assert_equal [@recipient.email], mail.to
    assert_match "New tour request", mail.subject
    assert_match @requester.name, mail.subject

    body = mail.body.to_s
    assert_match @requester.name, body
    assert_match @requester.email, body
    assert_match "Looking for office space for 3", body
    assert_match @location.name, body
  end
end
```

- [ ] **Step 2: Run, confirm fails**

Run: `bin/rails test test/mailers/tour_request_mailer_test.rb -v`
Expected: FAIL — mailer not defined.

- [ ] **Step 3: Create the mailer**

Create `app/mailers/tour_request_mailer.rb`:

```ruby
class TourRequestMailer < ApplicationMailer
  def new_request
    @recipient = params[:recipient]
    @activity  = params[:activity]
    @requester = @activity.user
    @location  = @activity.subject_type == "Location" ? @activity.subject : nil
    @operator  = @activity.operator
    @message   = @activity.payload["message"]

    mail(
      to: @recipient.email,
      subject: "New tour request: #{@requester.name}",
    )
  end
end
```

- [ ] **Step 4: Create email views**

Create `app/views/tour_request_mailer/new_request.html.erb`:

```erb
<h2>New tour request</h2>

<p><strong><%= @requester.name %></strong> requested a tour<% if @location %> at <strong><%= @location.name %></strong><% end %>.</p>

<ul>
  <li><strong>Email:</strong> <%= mail_to @requester.email %></li>
  <% if @requester.phone.present? %>
    <li><strong>Phone:</strong> <%= @requester.phone %></li>
  <% end %>
</ul>

<% if @message.present? %>
  <h3>Message</h3>
  <p><%= simple_format(@message) %></p>
<% end %>

<p>
  <%= link_to "Open in Jellyswitch",
              "https://#{@operator.subdomain}.jellyswitch.com/users/#{@requester.id}" %>
</p>
```

Create `app/views/tour_request_mailer/new_request.text.erb`:

```erb
New tour request

<%= @requester.name %> requested a tour<% if @location %> at <%= @location.name %><% end %>.

Email: <%= @requester.email %>
<% if @requester.phone.present? %>Phone: <%= @requester.phone %><% end %>

<% if @message.present? %>
Message:
<%= @message %>

<% end %>
Open in Jellyswitch: https://<%= @operator.subdomain %>.jellyswitch.com/users/<%= @requester.id %>
```

- [ ] **Step 5: Run mailer test, confirm passes**

Run: `bin/rails test test/mailers/tour_request_mailer_test.rb -v`
Expected: 1 run, all assertions pass.

- [ ] **Step 6: Re-run the adapter tests now that TourRequestMailer exists**

Run: `bin/rails test test/adapters/notifiable/tour_request_alert_test.rb -v`
Expected: 6 runs, all pass.

- [ ] **Step 7: Commit**

```bash
git add app/mailers/tour_request_mailer.rb app/views/tour_request_mailer test/mailers/tour_request_mailer_test.rb
git commit -m "TourRequestMailer#new_request (HTML + text views)"
```

---

## Task 12: Settings page — controller, view, tab nav

**Files:**
- Modify: `app/controllers/operator/settings_controller.rb`
- Modify: `app/views/operator/settings/_tab_layout.html.erb`
- Create: `app/views/operator/settings/tour_widget.html.erb`
- Test: `test/controllers/operator/settings_tour_widget_test.rb`

- [ ] **Step 1: Write failing test for the new settings page**

Create `test/controllers/operator/settings_tour_widget_test.rb`:

```ruby
require 'test_helper'

class Operator::SettingsTourWidgetTest < ActionDispatch::IntegrationTest
  setup do
    setup_initial_user_fixtures
    @admin = users(:cowork_tahoe_admin)
    log_in @admin
  end

  test "GET tour_widget renders as admin" do
    get settings_tour_widget_path, env: default_env
    assert_response :success
    assert_select "h2", /Tour Widget/i
  end

  test "GET tour_widget redirects when current user is not admin" do
    log_out
    log_in users(:cowork_tahoe_member)
    get settings_tour_widget_path, env: default_env
    assert_response :redirect
  end

  test "PATCH update_tour_widget persists settings" do
    patch update_tour_widget_path, env: default_env, params: {
      operator: {
        tour_widget_enabled: "1",
        tour_widget_thank_you_url: "https://example.com/thanks",
      }
    }
    assert_redirected_to settings_tour_widget_path
    operator = @admin.operator.reload
    assert operator.tour_widget_enabled
    assert_equal "https://example.com/thanks", operator.tour_widget_thank_you_url
  end

  test "PATCH update_tour_widget rejects javascript: URLs" do
    patch update_tour_widget_path, env: default_env, params: {
      operator: { tour_widget_thank_you_url: "javascript:alert(1)" }
    }
    assert_response :unprocessable_entity
  end
end
```

- [ ] **Step 2: Run, confirm fails**

Run: `bin/rails test test/controllers/operator/settings_tour_widget_test.rb -v`
Expected: FAIL — routes not wired to actions.

- [ ] **Step 3: Add actions to the settings controller**

Edit `app/controllers/operator/settings_controller.rb`. Locate the pattern used by the existing settings actions (e.g. `branding` / `update_branding`) and add:

```ruby
def tour_widget
  render layout: "operator_admin"   # use whatever layout the other settings pages use; copy from #branding
end

def update_tour_widget
  if @operator.update(tour_widget_params)
    redirect_to settings_tour_widget_path, notice: "Tour widget settings saved."
  else
    flash.now[:error] = @operator.errors.full_messages.to_sentence
    render :tour_widget, status: :unprocessable_entity
  end
end

private

def tour_widget_params
  params.require(:operator).permit(
    :tour_widget_enabled,
    :tour_widget_thank_you_url,
    :tour_widget_intro_html,
  )
end
```

(Note: read the existing `#branding` action first to mirror its `@operator` setup, before-filters, and layout choice. The `private` keyword above belongs at the bottom of the class — fold the param method into the existing `private` block.)

- [ ] **Step 4: Add nav tab**

Edit `app/views/operator/settings/_tab_layout.html.erb` — extend the `tabs` array:

```erb
tabs = [
  { key: :branding,           label: "Branding & Content", icon: "fas fa-paint-brush" },
  { key: :payments,           label: "Payments",           icon: "fab fa-stripe" },
  { key: :doors,              label: "Doors",              icon: "fas fa-door-open" },
  { key: :hours_and_address,  label: "Hours & Address",    icon: "fas fa-map-marker-alt" },
  { key: :wifi_and_pixels,    label: "WiFi & Pixels",      icon: "fas fa-wifi" },
  { key: :notifications,      label: "Notifications",      icon: "fas fa-envelope" },
  { key: :tour_widget,        label: "Tour Widget",        icon: "fas fa-paste" },
  { key: :modules,            label: "Modules",            icon: "fas fa-th-large" },
  { key: :policies,           label: "Policies",           icon: "fas fa-balance-scale" },
]
```

- [ ] **Step 5: Create the settings view**

Create `app/views/operator/settings/tour_widget.html.erb`:

```erb
<% provide(:title, "Tour Widget") %>

<%= render "tab_layout", active: :tour_widget do %>
  <%= form_with model: @operator, url: update_tour_widget_path, method: :patch, local: true do |f| %>
    <div class="form-group">
      <div class="custom-control custom-switch">
        <%= f.check_box :tour_widget_enabled, class: "custom-control-input", id: "tour_widget_enabled" %>
        <%= f.label :tour_widget_enabled, "Allow public tour requests", class: "custom-control-label" %>
      </div>
      <small class="form-text text-muted">When off, the public endpoint returns 404 to any visitor.</small>
    </div>

    <div class="form-group">
      <%= f.label :tour_widget_intro_html, "Intro text shown above the form" %>
      <%= f.rich_text_area :tour_widget_intro_html %>
    </div>

    <div class="form-group">
      <%= f.label :tour_widget_thank_you_url, "Custom thank-you redirect URL (optional)" %>
      <%= f.url_field :tour_widget_thank_you_url, class: "form-control", placeholder: "https://your-marketing-site.com/thanks" %>
      <small class="form-text text-muted">Blank = use Jellyswitch's hosted thank-you page.</small>
    </div>

    <%= f.submit "Save", class: "btn btn-primary" %>
  <% end %>

  <hr>

  <h3>Embed snippets</h3>

  <h5>Pin to a location (optional)</h5>
  <select id="tour-widget-location-picker" class="form-control mb-3">
    <option value="">All locations (visitors pick)</option>
    <% @operator.locations.where(visible: true).order(:name).each do |loc| %>
      <option value="<%= loc.id %>"><%= loc.name %></option>
    <% end %>
  </select>

  <h5>Iframe (recommended)</h5>
  <div class="input-group mb-3">
    <textarea id="iframe-snippet" class="form-control" rows="4" readonly></textarea>
    <button class="btn btn-outline-secondary" type="button" data-clipboard-target="iframe-snippet">Copy</button>
  </div>

  <h5>HTML form (advanced)</h5>
  <div class="input-group mb-3">
    <textarea id="form-snippet" class="form-control" rows="10" readonly></textarea>
    <button class="btn btn-outline-secondary" type="button" data-clipboard-target="form-snippet">Copy</button>
  </div>

  <h3 class="mt-4">Live preview</h3>
  <iframe id="widget-preview"
          src="<%= embed_tour_request_url(subdomain: @operator.subdomain, host: request.host_with_port) %>"
          width="100%" height="500" style="border: 1px solid #ddd; border-radius: 4px;"
          title="Tour widget preview">
  </iframe>

  <script>
    (function() {
      var picker = document.getElementById('tour-widget-location-picker');
      var iframeBox = document.getElementById('iframe-snippet');
      var formBox = document.getElementById('form-snippet');
      var preview = document.getElementById('widget-preview');
      var base = "<%= embed_tour_request_url(subdomain: @operator.subdomain, host: request.host_with_port).sub('http://', 'https://') %>";

      function render() {
        var path = base;
        if (picker.value) {
          path = path.replace(/\/?$/, "") + "/locations/" + picker.value;
        }
        iframeBox.value = '<iframe src="' + path + '" width="100%" height="600" style="border:none;" title="Request a tour"></iframe>';
        formBox.value = '<form action="' + path + '" method="post">\n' +
                        '  <input name="name" placeholder="Your name" required>\n' +
                        '  <input name="email" type="email" placeholder="Email" required>\n' +
                        '  <textarea name="message" placeholder="What are you looking for?"></textarea>\n' +
                        '  <input name="_hp" tabindex="-1" autocomplete="off" style="display:none">\n' +
                        '  <button type="submit">Request a tour</button>\n' +
                        '</form>';
        preview.src = path;
      }

      picker.addEventListener('change', render);

      document.querySelectorAll('[data-clipboard-target]').forEach(function(btn) {
        btn.addEventListener('click', function() {
          var box = document.getElementById(btn.getAttribute('data-clipboard-target'));
          box.select();
          document.execCommand('copy');
          btn.textContent = 'Copied!';
          setTimeout(function() { btn.textContent = 'Copy'; }, 1500);
        });
      });

      render();
    })();
  </script>
<% end %>
```

- [ ] **Step 6: Run settings tests, confirm pass**

Run: `bin/rails test test/controllers/operator/settings_tour_widget_test.rb -v`
Expected: 4 runs, all pass.

- [ ] **Step 7: Commit**

```bash
git add app/controllers/operator/settings_controller.rb app/views/operator/settings/_tab_layout.html.erb app/views/operator/settings/tour_widget.html.erb test/controllers/operator/settings_tour_widget_test.rb
git commit -m "Settings: Tour Widget tab with snippet generator + live preview"
```

---

## Task 13: ENV docs + final integration polish

**Files:**
- Modify: `.env.example` (or create if missing)

- [ ] **Step 1: Document new ENV vars**

Run: `ls .env.example 2>/dev/null` to see if it exists. If yes, append:

```
# Cloudflare Turnstile keys for the public tour-request widget.
# When TURNSTILE_SECRET is blank, Turnstile::Verifier short-circuits to success
# (useful for local dev). Set both in production.
TURNSTILE_SITEKEY=
TURNSTILE_SECRET=
```

If no `.env.example` exists, skip this step and note the vars in the PR description instead.

- [ ] **Step 2: Run the full test suite for the files we touched**

Run:
```
bin/rails test test/models/activity_test.rb test/models/operator_test.rb test/services/turnstile/verifier_test.rb test/adapters/notifiable/tour_request_alert_test.rb test/mailers/tour_request_mailer_test.rb test/controllers/embed/tour_requests_controller_test.rb test/controllers/operator/settings_tour_widget_test.rb -v
```
Expected: All green.

- [ ] **Step 3: Run a broader regression**

Run: `bin/rails test test/models test/controllers/operator -q`
Expected: Existing tests still pass (no regressions from adding `tour_request` to `Activity::KINDS` or extending the settings nav).

If any pre-existing tests fail that weren't failing before, fix them; if they're skipped or flaky per known memory entries (Test suite cleanup May 2026), leave them.

- [ ] **Step 4: Commit**

```bash
git add .env.example
git commit -m "Document TURNSTILE_SITEKEY/TURNSTILE_SECRET in .env.example"
```

---

## Task 14: Manual smoke test (verification-before-completion)

**Files:** none — manual verification.

- [ ] **Step 1: Boot the server**

Run: `bin/rails server` in a separate terminal.

- [ ] **Step 2: Log in as the Untethered admin and open the new Settings page**

Open in browser:
```
http://untethered.lvh.me:3000/operator/settings/tour_widget
```
(Use the test credentials from `reference_test_accounts.md` memory; `lvh.me` resolves to 127.0.0.1 and works for subdomain routing in dev.)

Expected: Settings page renders with disabled state, snippet boxes show iframe + HTML form HTML, live preview iframe shows the "Tour widget is not configured" 404 (because `tour_widget_enabled` is false).

- [ ] **Step 3: Enable + save**

Toggle "Allow public tour requests" → Save. Verify success flash.

- [ ] **Step 4: Live preview now renders the form**

Reload the page. The preview iframe should now show the actual tour-request form with location picker (Untethered has multiple locations).

- [ ] **Step 5: Submit a tour request from the preview**

Fill in name, email, message. Submit. Expected: redirected to the Jellyswitch-hosted thank-you page.

- [ ] **Step 6: Verify side effects in Rails console**

In a new terminal: `bin/rails c -e development`
```ruby
User.where(operator: Operator.find_by(subdomain: "untethered")).order(created_at: :desc).first
Activity.where(kind: "tour_request").order(occurred_at: :desc).first
```
Expected: new User row + new Activity row with correct payload + subject (Location).

- [ ] **Step 7: Verify the email landed**

Check MailCatcher (or whatever local mail receiver this dev env uses — `letter_opener`, `mailcatcher`, `bin/rails console -e development; ActionMailer::Base.deliveries.last`). Expected: one email per admin/GM recipient.

- [ ] **Step 8: Verify the Person timeline shows it**

Open `http://untethered.lvh.me:3000/users/<id>` for the new user. Expected: Activity timeline shows the tour request under the Tours tab/group.

- [ ] **Step 9: Test honeypot**

In browser dev tools, fill the form's hidden `_hp` field, then submit. Expected: 200 OK response, no new User/Activity created (verify in console).

- [ ] **Step 10: Test rate limit**

In a terminal, fire 6 curl POSTs quickly:
```bash
for i in {1..6}; do
  curl -i -X POST http://untethered.lvh.me:3000/embed/tour_request/untethered \
    -d "name=Rate$i" -d "email=rate$i@x.com" -d "location_id=<LOCATION_ID>"
done
```
Expected: First 5 → 302/303 redirect. 6th → 429 Too Many Requests.

(Skip this if Rack::Attack is disabled in dev per the initializer in Task 3.)

- [ ] **Step 11: Visual check the iframe in a hostile environment**

Create `/tmp/test-embed.html`:
```html
<!doctype html>
<html><body>
  <h1>Marketing Site Test</h1>
  <iframe src="http://untethered.lvh.me:3000/embed/tour_request/untethered"
          width="100%" height="600" style="border:none;"></iframe>
</body></html>
```
Open it in the browser. Expected: form renders inside the iframe — no `X-Frame-Options: DENY` block.

- [ ] **Step 12: Mark verification complete**

Once all 11 manual checks pass, the PR is ready.

---

## Task 15: Open the pull request

- [ ] **Step 1: Push branch + open PR**

```bash
git push -u origin claude/peaceful-moser-e7e141

gh pr create --title "Tour Request Widget: embed form for operator marketing sites" --body "$(cat <<'EOF'
## Summary
- New public endpoint `/embed/tour_request/:subdomain` (GET form + POST submission, iframe-friendly, CSRF-skipped, CORS-open).
- Captures `User + Activity(:tour_request)` — strictly additive, no Lead rows.
- Spam mitigation: honeypot, Rack::Attack throttle (5/min/IP on `/embed/*`), Cloudflare Turnstile.
- Notifications: push + email fan-out to operator admins + the requested location's general/community managers.
- Operator Settings UI at `/operator/settings/tour_widget` with live preview, iframe + HTML form copy-to-clipboard snippets, optional per-location pinning, and a configurable thank-you redirect URL.
- Multi-location aware: location picker appears when operator has >1 visible location; snippet can pin a location for location-specific marketing pages.

Spec: [docs/superpowers/specs/2026-05-17-tour-request-widget-design.md](docs/superpowers/specs/2026-05-17-tour-request-widget-design.md)
Plan: [docs/superpowers/plans/2026-05-17-tour-request-widget.md](docs/superpowers/plans/2026-05-17-tour-request-widget.md)

## Required for production
- Set `TURNSTILE_SITEKEY` and `TURNSTILE_SECRET` env vars on Heroku.
- Each operator must flip `Settings → Tour Widget → Allow public tour requests` on before their endpoint will accept traffic. Default off.

## Test plan
- [x] Embed controller request specs (GET render, GET pinned location, GET frame headers, 404s, POST happy path, POST existing user reuse, POST honeypot, POST Turnstile fail, POST rate limit, POST redirect to operator URL)
- [x] Notifiable::TourRequestAlert adapter (recipients fan-out, dedup, kind gate)
- [x] TourRequestMailer (subject, recipient, body content)
- [x] Turnstile::Verifier service (short-circuit, success, fail, network error fail-closed)
- [x] Operator settings tour_widget request specs (admin only, persist, URL validation)
- [x] Manual smoke test on lvh.me — form renders, submits, creates Person + Activity, sends emails, honeypot drops silently, rate limit returns 429, iframe loads cross-origin

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## Self-review checklist (run after writing this plan)

1. **Spec coverage** — every spec section mapped to a task: ✅
   - Architecture overview → Tasks 6-9
   - URL surface → Task 6
   - Data model → Tasks 1, 2, 5
   - Controllers → Tasks 7, 8, 12
   - Models/services (Turnstile, Notifiable, Mailer) → Tasks 4, 10, 11
   - Spam mitigation → Tasks 3 (Rack::Attack), 4 (Turnstile), 8 (honeypot), 9 (tests)
   - Operator settings UI → Task 12
   - Test plan → distributed across Tasks 2, 4, 5, 7-12
   - Migration order → Task 1
   - ENV / config → Task 13

2. **Placeholder scan** — no TBD/TODO/implement-later/add-appropriate-X language found.

3. **Type consistency** — `Notifiable::TourRequestAlert#recipients` returns array; controller calls `SendNotificationsJob.perform_later(activity, "TourRequestAlert")` (Activity model already uses this exact pattern for `PointOfContactAlert`); `Turnstile::Verifier::Result` has `success?` boolean used consistently in controller + tests.
