# Rails Settings Consolidation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Consolidate three scattered Rails admin pages (operator-edit, `/customization`, `/app_configs`) plus the Stripe Connect modal into a single `/operator/settings/{tab}` surface with 8 tabs, and establish the project-wide `HasDollars` convention so money fields display dollars while DB columns stay in cents.

**Architecture:** One `Operator::SettingsController` with action-per-tab (8 GET + 7 PATCH + 1 POST + helpers). Each tab gets its own view, its own strong-params method, and its own Save button. Shared `_tab_layout` partial provides the left rail. Doors tab embeds existing `Operator::DoorsController#index` as a Turbo Frame. Payments tab reuses the existing Stripe Connect OAuth modal. Legacy URLs 301 → new tabs. `/app_configs` survives as a super-admin-only page.

**Tech Stack:** Rails 8.1, vanilla `form_with` / `form_for` (no simple_form), Minitest + RSpec, Turbo (Frames + Drive), Bootstrap, Active Storage, ActsAsTenant.

**Spec:** [docs/superpowers/specs/2026-05-16-rails-settings-consolidation-design.md](../specs/2026-05-16-rails-settings-consolidation-design.md) (commit `789a5625`).

---

## File Structure

### Created

```
app/controllers/operator/settings_controller.rb     # all 17 actions
app/models/concerns/has_dollars.rb                  # dollars → cents virtual attr macro
app/views/operator/settings/_tab_layout.html.erb    # shared left-rail wrapper
app/views/operator/settings/branding.html.erb       # tab 1
app/views/operator/settings/payments.html.erb       # tab 2 (no form)
app/views/operator/settings/doors.html.erb          # tab 3
app/views/operator/settings/hours_and_address.html.erb  # tab 4
app/views/operator/settings/wifi_and_pixels.html.erb    # tab 5
app/views/operator/settings/notifications.html.erb  # tab 6
app/views/operator/settings/modules.html.erb        # tab 7
app/views/operator/settings/policies.html.erb       # tab 8
test/models/concerns/has_dollars_test.rb
spec/requests/operator/settings/branding_spec.rb
spec/requests/operator/settings/payments_spec.rb
spec/requests/operator/settings/doors_spec.rb
spec/requests/operator/settings/hours_and_address_spec.rb
spec/requests/operator/settings/wifi_and_pixels_spec.rb
spec/requests/operator/settings/notifications_spec.rb
spec/requests/operator/settings/modules_spec.rb
spec/requests/operator/settings/policies_spec.rb
spec/requests/operator/settings/legacy_redirects_spec.rb
test/system/operator/settings_navigation_test.rb
```

### Modified

```
config/routes.rb                                    # settings resource + legacy redirects
app/models/operator.rb                              # include HasDollars; dollars :day_pass_cost
app/models/location.rb                              # include HasDollars; dollars :hourly_rate, :credit_cost, :childcare_reservation_cost
app/views/operator/doors/index.html.erb             # wrap content in turbo_frame_tag "doors_list"
app/controllers/operator/operators_controller.rb    # delete #edit + #update; keep #stripe_connect_setup
app/controllers/landing_controller.rb               # delete #customization
app/controllers/operator/app_configs_controller.rb  # add before_action superadmin? gate
app/adapters/navigation/default.rb                  # replace Customization + App Config with Settings
app/views/operator/modules/index.html.erb           # remove Stripe Connect trigger
app/views/operator/onboarding/finish_stripe_connect.rb  # (or wherever post-OAuth redirect lives) → /operator/settings/payments
```

### Deleted

```
app/views/operator/operators/edit.html.erb
app/views/operator/operators/_form.html.erb         # (only if not used by another action; verify in Task 19)
app/views/operator/landing/customization.html.erb
```

---

## Task 1: HasDollars concern with unit tests

**Files:**
- Create: `app/models/concerns/has_dollars.rb`
- Create: `test/models/concerns/has_dollars_test.rb`

- [ ] **Step 1: Write the failing test**

`test/models/concerns/has_dollars_test.rb`:

```ruby
require "test_helper"

class HasDollarsTest < ActiveSupport::TestCase
  # Lightweight test class — no DB, just attribute storage
  class Fake
    include ActiveModel::Model
    include ActiveModel::Attributes
    include HasDollars

    attribute :price_in_cents, :integer
    dollars :price
  end

  test "reads dollars from cents column" do
    fake = Fake.new(price_in_cents: 2599)
    assert_in_delta 25.99, fake.price, 0.0001
  end

  test "writes dollars to cents column" do
    fake = Fake.new
    fake.price = "40.99"
    assert_equal 4099, fake.price_in_cents
  end

  test "handles whole-dollar string" do
    fake = Fake.new
    fake.price = "25"
    assert_equal 2500, fake.price_in_cents
  end

  test "handles numeric input" do
    fake = Fake.new
    fake.price = 12.5
    assert_equal 1250, fake.price_in_cents
  end

  test "blank input clears cents to nil" do
    fake = Fake.new(price_in_cents: 500)
    fake.price = ""
    assert_nil fake.price_in_cents
  end

  test "nil cents reads as nil dollars" do
    fake = Fake.new(price_in_cents: nil)
    assert_nil fake.price
  end

  test "accepts multiple field names" do
    klass = Class.new do
      include ActiveModel::Model
      include ActiveModel::Attributes
      include HasDollars

      attribute :a_in_cents, :integer
      attribute :b_in_cents, :integer
      dollars :a, :b
    end

    obj = klass.new(a_in_cents: 100, b_in_cents: 200)
    assert_equal 1.0, obj.a
    assert_equal 2.0, obj.b
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

```
bin/rails test test/models/concerns/has_dollars_test.rb
```

Expected: all tests FAIL with `NameError: uninitialized constant HasDollars`.

- [ ] **Step 3: Write the concern**

`app/models/concerns/has_dollars.rb`:

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
          if value.is_a?(String) && value.strip.empty? || value.nil?
            write_attribute(cents_attr, nil)
          else
            write_attribute(cents_attr, (BigDecimal(value.to_s) * 100).to_i)
          end
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

```
bin/rails test test/models/concerns/has_dollars_test.rb
```

Expected: all 7 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add app/models/concerns/has_dollars.rb test/models/concerns/has_dollars_test.rb
git commit -m "Add HasDollars concern for dollars-in-UI / cents-in-DB convention"
```

---

## Task 2: Apply HasDollars to Operator and Location

**Files:**
- Modify: `app/models/operator.rb` (add `include HasDollars; dollars :day_pass_cost`)
- Modify: `app/models/location.rb` (add `include HasDollars; dollars :hourly_rate, :credit_cost, :childcare_reservation_cost`)
- Create: `test/models/operator_dollars_test.rb`

- [ ] **Step 1: Write the failing test**

`test/models/operator_dollars_test.rb`:

```ruby
require "test_helper"

class OperatorDollarsTest < ActiveSupport::TestCase
  test "Operator#day_pass_cost reads dollars from day_pass_cost_in_cents" do
    operator = operators(:untethered)
    operator.update!(day_pass_cost_in_cents: 2500)
    assert_in_delta 25.00, operator.day_pass_cost, 0.0001
  end

  test "Operator#day_pass_cost= writes dollars to day_pass_cost_in_cents" do
    operator = operators(:untethered)
    operator.day_pass_cost = "40.99"
    assert_equal 4099, operator.day_pass_cost_in_cents
  end

  test "Location responds to dollars accessors" do
    location = locations(:untethered_main)
    assert_respond_to location, :hourly_rate
    assert_respond_to location, :hourly_rate=
    assert_respond_to location, :credit_cost
    assert_respond_to location, :childcare_reservation_cost
  end
end
```

(Adjust fixture names to match what exists — use `bin/rails test` to discover the right ones if `:untethered` / `:untethered_main` don't resolve.)

- [ ] **Step 2: Run test to verify it fails**

```
bin/rails test test/models/operator_dollars_test.rb
```

Expected: FAIL with `NoMethodError: undefined method 'day_pass_cost' for #<Operator>`.

- [ ] **Step 3: Add the concern to both models**

Edit `app/models/operator.rb` — find the class declaration and add near the top of the class body (after `acts_as_tenant` or similar associations):

```ruby
include HasDollars
dollars :day_pass_cost
```

Edit `app/models/location.rb` — same pattern:

```ruby
include HasDollars
dollars :hourly_rate, :credit_cost, :childcare_reservation_cost
```

- [ ] **Step 4: Run test to verify it passes**

```
bin/rails test test/models/operator_dollars_test.rb
```

Expected: all 3 tests PASS. Also run the full model test suite to confirm no regressions:

```
bin/rails test test/models/
```

Expected: green.

- [ ] **Step 5: Commit**

```bash
git add app/models/operator.rb app/models/location.rb test/models/operator_dollars_test.rb
git commit -m "Declare dollars accessors on Operator and Location"
```

---

## Task 3: Routes + empty controller skeleton

**Files:**
- Create: `app/controllers/operator/settings_controller.rb`
- Modify: `config/routes.rb`
- Create: `spec/requests/operator/settings/skeleton_spec.rb`

- [ ] **Step 1: Write the failing spec**

`spec/requests/operator/settings/skeleton_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Operator::SettingsController skeleton", type: :request do
  let(:operator)  { Operator.find_by(subdomain: "untethered") || FactoryBot.create(:operator, subdomain: "untethered") }
  let(:location)  { operator.locations.first || FactoryBot.create(:location, operator: operator) }
  let(:admin)     { User.find_by(email: "admin@untethered.test") || FactoryBot.create(:user, :admin, operator: operator, current_location: location) }

  before do
    ActsAsTenant.current_tenant = operator
    host! "untethered.example.com"
    sign_in(admin)  # use whatever sign-in helper the app has (devise or session-based)
  end

  it "GET /operator/settings redirects to /operator/settings/branding" do
    get "/operator/settings"
    expect(response).to redirect_to("/operator/settings/branding")
  end

  it "GET /operator/settings/branding returns 200" do
    get "/operator/settings/branding"
    expect(response).to have_http_status(:ok)
  end
end
```

(If the app uses a different sign-in helper, copy the pattern from `spec/requests/operator/locations_spec.rb` or similar existing operator spec — adjust this `before` block to match.)

- [ ] **Step 2: Run spec to verify it fails**

```
bundle exec rspec spec/requests/operator/settings/skeleton_spec.rb
```

Expected: FAIL — routing error `No route matches [GET] "/operator/settings"`.

- [ ] **Step 3: Add routes**

Edit `config/routes.rb`. Find the `namespace :operator do` block (search for `namespace :operator`). Inside it, add:

```ruby
resource :settings, only: [], controller: "settings" do
  collection do
    get :branding
    patch :update_branding
    get :payments
    get :doors
    patch :update_doors
    post :import_doors
    get :hours_and_address
    patch :update_hours_and_address
    get :wifi_and_pixels
    patch :update_wifi_and_pixels
    get :notifications
    patch :update_notifications
    get :modules
    patch :update_modules
    get :policies
    patch :update_policies
  end
end
get "/operator/settings", to: "operator/settings#index"
```

Note: Rails won't auto-route a `resource :settings` to `Operator::SettingsController` unless it's inside the `namespace :operator` block; the explicit `controller: "settings"` is belt-and-suspenders.

- [ ] **Step 4: Create the skeleton controller**

`app/controllers/operator/settings_controller.rb`:

```ruby
class Operator::SettingsController < ApplicationController
  before_action :require_admin!

  def index
    redirect_to operator_settings_branding_path
  end

  def branding;             end
  def payments;             end
  def doors;                end
  def hours_and_address;    end
  def wifi_and_pixels;      end
  def notifications;        end
  def modules;              end
  def policies;             end

  def update_branding;             head :not_implemented; end
  def update_doors;                head :not_implemented; end
  def import_doors;                head :not_implemented; end
  def update_hours_and_address;    head :not_implemented; end
  def update_wifi_and_pixels;      head :not_implemented; end
  def update_notifications;        head :not_implemented; end
  def update_modules;              head :not_implemented; end
  def update_policies;             head :not_implemented; end

  private

  def require_admin!
    redirect_to root_path, alert: "Admins only." unless current_user&.admin? || current_user&.superadmin?
  end
end
```

Also create placeholder views — one line each so the GET actions don't crash:

```
app/views/operator/settings/branding.html.erb           → <h1>Branding & Content</h1>
app/views/operator/settings/payments.html.erb           → <h1>Payments</h1>
app/views/operator/settings/doors.html.erb              → <h1>Doors</h1>
app/views/operator/settings/hours_and_address.html.erb  → <h1>Hours &amp; Address</h1>
app/views/operator/settings/wifi_and_pixels.html.erb    → <h1>WiFi &amp; Pixels</h1>
app/views/operator/settings/notifications.html.erb      → <h1>Notifications</h1>
app/views/operator/settings/modules.html.erb            → <h1>Modules</h1>
app/views/operator/settings/policies.html.erb           → <h1>Policies</h1>
```

- [ ] **Step 5: Run spec to verify it passes**

```
bundle exec rspec spec/requests/operator/settings/skeleton_spec.rb
```

Expected: both examples PASS.

- [ ] **Step 6: Commit**

```bash
git add config/routes.rb app/controllers/operator/settings_controller.rb app/views/operator/settings/ spec/requests/operator/settings/skeleton_spec.rb
git commit -m "Scaffold Operator::SettingsController with empty tab actions"
```

---

## Task 4: Shared tab layout partial

**Files:**
- Create: `app/views/operator/settings/_tab_layout.html.erb`
- Modify: each of the 8 tab views to render through this layout

- [ ] **Step 1: Create the layout partial**

`app/views/operator/settings/_tab_layout.html.erb`:

```erb
<%
  tabs = [
    { key: :branding,           label: "Branding & Content", icon: "fas fa-paint-brush" },
    { key: :payments,           label: "Payments",           icon: "fab fa-stripe" },
    { key: :doors,              label: "Doors",              icon: "fas fa-door-open" },
    { key: :hours_and_address,  label: "Hours & Address",    icon: "fas fa-map-marker-alt" },
    { key: :wifi_and_pixels,    label: "WiFi & Pixels",      icon: "fas fa-wifi" },
    { key: :notifications,      label: "Notifications",      icon: "fas fa-envelope" },
    { key: :modules,            label: "Modules",            icon: "fas fa-th-large" },
    { key: :policies,           label: "Policies",           icon: "fas fa-balance-scale" },
  ]
  active = local_assigns[:active] || params[:action].to_sym
%>

<div class="row">
  <aside class="col-md-3 col-lg-2 mb-4">
    <div class="list-group">
      <% tabs.each do |tab| %>
        <%= link_to send("operator_settings_#{tab[:key]}_path"),
                    class: "list-group-item list-group-item-action d-flex align-items-center #{'active' if active == tab[:key]}",
                    data: { "turbo-action" => "advance" } do %>
          <i class="<%= tab[:icon] %> text-muted mr-2" style="width: 18px;"></i>
          <%= tab[:label] %>
        <% end %>
      <% end %>
    </div>
  </aside>
  <main class="col-md-9 col-lg-10">
    <h2 class="mb-3"><%= tabs.find { |t| t[:key] == active }[:label] %></h2>
    <%= yield %>
  </main>
</div>
```

- [ ] **Step 2: Update each tab view to render through the layout**

For each of the 8 tab views, replace the placeholder content with this pattern (`branding.html.erb` shown — repeat structure for the other 7, changing only the content inside the block):

```erb
<%= render layout: "operator/settings/tab_layout", locals: { active: :branding } do %>
  <p>Branding & Content tab — fields coming in Task 5.</p>
<% end %>
```

For `payments.html.erb`: `locals: { active: :payments }`. Same for each.

- [ ] **Step 3: Manually verify in browser**

```
bin/rails server
```

Open http://localhost:3000/operator/settings (signed in as an admin). Click each tab — sidebar should highlight active tab, no JS errors in console.

- [ ] **Step 4: Commit**

```bash
git add app/views/operator/settings/
git commit -m "Add shared tab layout partial for Operator::SettingsController"
```

---

## Task 5: Branding tab — fields, GET, PATCH

**Files:**
- Modify: `app/views/operator/settings/branding.html.erb`
- Modify: `app/controllers/operator/settings_controller.rb` (real `update_branding`)
- Create: `spec/requests/operator/settings/branding_spec.rb`

- [ ] **Step 1: Write the failing spec**

`spec/requests/operator/settings/branding_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Operator::Settings Branding", type: :request do
  include OperatorSettingsHelpers  # add this helper in spec/support — see Step 1b

  let(:operator) { sign_in_as_admin }

  describe "GET /operator/settings/branding" do
    it "returns 200 and renders the snippet field" do
      get "/operator/settings/branding"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(operator.snippet) if operator.snippet.present?
      expect(response.body).to include("name=\"operator[snippet]\"")
    end
  end

  describe "PATCH /operator/settings/update_branding" do
    it "updates branding fields" do
      patch "/operator/settings/update_branding", params: {
        operator: { snippet: "New snippet", membership_text: "New membership text" }
      }
      expect(response).to redirect_to(operator_settings_branding_path)
      expect(operator.reload.snippet).to eq("New snippet")
      expect(operator.membership_text).to eq("New membership text")
    end

    it "rejects params outside the branding whitelist" do
      patch "/operator/settings/update_branding", params: {
        operator: { kisi_api_key: "should not change" }
      }
      operator.reload
      expect(operator.kisi_api_key).not_to eq("should not change")
    end
  end
end
```

Step 1b: Create the spec helper at `spec/support/operator_settings_helpers.rb`:

```ruby
module OperatorSettingsHelpers
  def sign_in_as_admin
    operator = Operator.find_by(subdomain: "untethered") || FactoryBot.create(:operator, subdomain: "untethered")
    location = operator.locations.first || FactoryBot.create(:location, operator: operator)
    admin    = FactoryBot.create(:user, :admin, operator: operator, current_location: location)
    ActsAsTenant.current_tenant = operator
    host! "untethered.example.com"
    post "/session", params: { session: { email: admin.email, password: "password" } }
    operator
  end
end
```

(Adapt the sign-in step to whatever pattern existing operator request specs use — copy from `spec/requests/operator/locations_spec.rb` if it exists.)

Ensure `spec/rails_helper.rb` autoloads `spec/support`:

```ruby
Dir[Rails.root.join("spec/support/**/*.rb")].each { |f| require f }
```

(Add this line if not already present.)

- [ ] **Step 2: Run spec to verify it fails**

```
bundle exec rspec spec/requests/operator/settings/branding_spec.rb
```

Expected: FAIL — `update_branding` returns 501 (`head :not_implemented`).

- [ ] **Step 3: Implement the form view**

`app/views/operator/settings/branding.html.erb`:

```erb
<%= render layout: "operator/settings/tab_layout", locals: { active: :branding } do %>
  <%= form_with model: current_operator, url: operator_settings_update_branding_path, method: :patch, html: { multipart: true } do |f| %>
    <%= render "shared/error_messages", model: current_operator %>

    <div class="form-group">
      <%= f.label :logo_image, "Logo" %>
      <% if current_operator.logo_image.attached? %>
        <div class="mb-2"><%= image_tag current_operator.logo_image, width: 88 %></div>
      <% end %>
      <%= f.file_field :logo_image, class: "form-control-file" %>
    </div>

    <div class="form-group">
      <%= f.label :snippet, "Short description" %>
      <%= f.text_field :snippet, class: "form-control" %>
      <small class="form-text text-muted">Shown on your public landing page.</small>
    </div>

    <div class="form-group">
      <%= f.label :membership_text, "Membership info" %>
      <%= f.text_area :membership_text, rows: 4, class: "form-control" %>
    </div>

    <div class="form-group">
      <%= f.label :terms_of_service, "Terms of service" %>
      <% if current_operator.terms_of_service.attached? %>
        <div class="mb-2"><%= link_to "Current ToS", url_for(current_operator.terms_of_service), target: "_blank" %></div>
      <% end %>
      <%= f.file_field :terms_of_service, class: "form-control-file" %>
    </div>

    <div class="form-group">
      <%= f.label :google_reviews_url, "Google Reviews URL" %>
      <%= f.url_field :google_reviews_url, class: "form-control" %>
    </div>

    <%= f.submit "Save Branding", class: "btn btn-primary" %>
  <% end %>
<% end %>
```

- [ ] **Step 4: Implement the controller actions**

In `app/controllers/operator/settings_controller.rb`, replace the empty `def branding` and `def update_branding`:

```ruby
def branding
  @operator = current_operator
end

def update_branding
  if current_operator.update(branding_params)
    redirect_to operator_settings_branding_path, notice: "Branding saved."
  else
    render :branding, status: :unprocessable_entity
  end
end

private

def branding_params
  params.require(:operator).permit(:logo_image, :snippet, :membership_text, :terms_of_service, :google_reviews_url)
end
```

Add `current_operator` helper if not already available (likely is — used elsewhere in the codebase).

- [ ] **Step 5: Run spec to verify it passes**

```
bundle exec rspec spec/requests/operator/settings/branding_spec.rb
```

Expected: all 3 examples PASS.

- [ ] **Step 6: Commit**

```bash
git add spec/requests/operator/settings/branding_spec.rb spec/support/operator_settings_helpers.rb app/views/operator/settings/branding.html.erb app/controllers/operator/settings_controller.rb
git commit -m "Branding tab: render fields, save via update_branding"
```

---

## Task 6: Notifications tab (operator + Mailchimp section)

**Files:**
- Modify: `app/views/operator/settings/notifications.html.erb`
- Modify: `app/controllers/operator/settings_controller.rb` (real `update_notifications` + `notifications_params`)
- Create: `spec/requests/operator/settings/notifications_spec.rb`

- [ ] **Step 1: Write the failing spec**

`spec/requests/operator/settings/notifications_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Operator::Settings Notifications", type: :request do
  include OperatorSettingsHelpers
  let(:operator) { sign_in_as_admin }

  it "renders all 10 notification toggles + Mailchimp + sender_email" do
    get "/operator/settings/notifications"
    expect(response).to have_http_status(:ok)
    %w[email_enabled reservation_notifications membership_notifications signup_notifications
       day_pass_notifications member_feedback_notifications checkin_notifications
       refund_notifications post_notifications paid_room_reservation_notifications].each do |attr|
      expect(response.body).to include("operator[#{attr}]"), "missing toggle: #{attr}"
    end
    expect(response.body).to include("operator[sender_email]")
    expect(response.body).to include("operator[mailchimp_api_key]")
    expect(response.body).to include("operator[mailchimp_audience_id]")
  end

  it "saves notification toggles + Mailchimp fields" do
    patch "/operator/settings/update_notifications", params: {
      operator: {
        signup_notifications: "1",
        sender_email: "noreply@untethered.com",
        mailchimp_api_key: "mc-abc",
        mailchimp_audience_id: "aud-1",
      }
    }
    expect(response).to redirect_to(operator_settings_notifications_path)
    expect(operator.reload.signup_notifications).to be true
    expect(operator.sender_email).to eq("noreply@untethered.com")
    expect(operator.mailchimp_api_key).to eq("mc-abc")
    expect(operator.mailchimp_audience_id).to eq("aud-1")
  end

  it "rejects params outside the notifications whitelist" do
    patch "/operator/settings/update_notifications", params: { operator: { snippet: "should not change" } }
    expect(operator.reload.snippet).not_to eq("should not change")
  end
end
```

- [ ] **Step 2: Run spec to verify it fails**

```
bundle exec rspec spec/requests/operator/settings/notifications_spec.rb
```

Expected: FAIL.

- [ ] **Step 3: Implement the view**

`app/views/operator/settings/notifications.html.erb`:

```erb
<%= render layout: "operator/settings/tab_layout", locals: { active: :notifications } do %>
  <%= form_with model: current_operator, url: operator_settings_update_notifications_path, method: :patch do |f| %>
    <%= render "shared/error_messages", model: current_operator %>

    <h5 class="mt-2">Email notifications</h5>
    <p class="text-muted small">Choose which operator-facing emails you'd like to receive.</p>

    <% [
      [:email_enabled, "Master switch: send any operator-facing emails"],
      [:signup_notifications, "New member signups"],
      [:checkin_notifications, "Member check-ins"],
      [:day_pass_notifications, "Day pass purchases"],
      [:membership_notifications, "Membership changes"],
      [:reservation_notifications, "Room reservations (free)"],
      [:paid_room_reservation_notifications, "Room reservations (paid)"],
      [:refund_notifications, "Refunds processed"],
      [:member_feedback_notifications, "Member feedback submitted"],
      [:post_notifications, "Bulletin board posts"],
    ].each do |attr, label| %>
      <div class="form-check">
        <%= f.check_box attr, class: "form-check-input" %>
        <%= f.label attr, label, class: "form-check-label" %>
      </div>
    <% end %>

    <hr class="my-4">

    <h5>Sender address</h5>
    <div class="form-group">
      <%= f.label :sender_email, "From: address for outgoing emails" %>
      <%= f.email_field :sender_email, class: "form-control" %>
    </div>

    <hr class="my-4">

    <h5>Mailchimp</h5>
    <p class="text-muted small">Sync new members to a Mailchimp audience.</p>
    <div class="form-group">
      <%= f.label :mailchimp_api_key, "API key" %>
      <%= f.text_field :mailchimp_api_key, class: "form-control" %>
    </div>
    <div class="form-group">
      <%= f.label :mailchimp_audience_id, "Audience ID" %>
      <%= f.text_field :mailchimp_audience_id, class: "form-control" %>
    </div>

    <%= f.submit "Save Notifications", class: "btn btn-primary" %>
  <% end %>
<% end %>
```

- [ ] **Step 4: Implement the controller action + strong params**

In `app/controllers/operator/settings_controller.rb`:

```ruby
def notifications
  @operator = current_operator
end

def update_notifications
  if current_operator.update(notifications_params)
    redirect_to operator_settings_notifications_path, notice: "Notifications saved."
  else
    render :notifications, status: :unprocessable_entity
  end
end

# in private section
def notifications_params
  params.require(:operator).permit(
    :email_enabled, :reservation_notifications, :membership_notifications,
    :signup_notifications, :day_pass_notifications, :member_feedback_notifications,
    :checkin_notifications, :refund_notifications, :post_notifications,
    :paid_room_reservation_notifications, :sender_email,
    :mailchimp_api_key, :mailchimp_audience_id
  )
end
```

- [ ] **Step 5: Run spec to verify it passes**

```
bundle exec rspec spec/requests/operator/settings/notifications_spec.rb
```

Expected: all 3 examples PASS.

- [ ] **Step 6: Commit**

```bash
git add app/views/operator/settings/notifications.html.erb app/controllers/operator/settings_controller.rb spec/requests/operator/settings/notifications_spec.rb
git commit -m "Notifications tab: 10 toggles + Mailchimp + sender_email"
```

---

## Task 7: Modules tab (9 product-module toggles)

**Files:**
- Modify: `app/views/operator/settings/modules.html.erb`
- Modify: `app/controllers/operator/settings_controller.rb`
- Create: `spec/requests/operator/settings/modules_spec.rb`

- [ ] **Step 1: Write the failing spec**

`spec/requests/operator/settings/modules_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Operator::Settings Modules", type: :request do
  include OperatorSettingsHelpers
  let(:operator) { sign_in_as_admin }

  it "renders all 9 module toggles" do
    get "/operator/settings/modules"
    expect(response).to have_http_status(:ok)
    %w[announcements_enabled events_enabled door_integration_enabled rooms_enabled
       offices_enabled bulletin_board_enabled credits_enabled childcare_enabled crm_enabled].each do |attr|
      expect(response.body).to include("operator[#{attr}]"), "missing toggle: #{attr}"
    end
    expect(response.body).to include("dormant"), "expected credits dormant warning"
  end

  it "saves module toggles" do
    patch "/operator/settings/update_modules", params: {
      operator: { announcements_enabled: "0", rooms_enabled: "1" }
    }
    expect(response).to redirect_to(operator_settings_modules_path)
    operator.reload
    expect(operator.announcements_enabled).to be false
    expect(operator.rooms_enabled).to be true
  end
end
```

- [ ] **Step 2: Run spec to verify it fails**

```
bundle exec rspec spec/requests/operator/settings/modules_spec.rb
```

Expected: FAIL.

- [ ] **Step 3: Implement the view**

`app/views/operator/settings/modules.html.erb`:

```erb
<%= render layout: "operator/settings/tab_layout", locals: { active: :modules } do %>
  <%= form_with model: current_operator, url: operator_settings_update_modules_path, method: :patch do |f| %>
    <%= render "shared/error_messages", model: current_operator %>
    <p class="text-muted">Turn product modules on or off for your space.</p>

    <% [
      [:announcements_enabled, "Announcements"],
      [:events_enabled, "Events"],
      [:door_integration_enabled, "Door Integration"],
      [:rooms_enabled, "Rooms & Reservations"],
      [:offices_enabled, "Offices & Leases"],
      [:bulletin_board_enabled, "Bulletin Board"],
      [:childcare_enabled, "Childcare"],
      [:crm_enabled, "CRM"],
    ].each do |attr, label| %>
      <div class="form-check">
        <%= f.check_box attr, class: "form-check-input" %>
        <%= f.label attr, label, class: "form-check-label" %>
      </div>
    <% end %>

    <div class="form-check">
      <%= f.check_box :credits_enabled, class: "form-check-input" %>
      <%= f.label :credits_enabled, "Credits", class: "form-check-label" %>
      <small class="form-text text-warning">
        Credits is currently <strong>dormant</strong> — toggling on may not behave as expected.
      </small>
    </div>

    <%= f.submit "Save Modules", class: "btn btn-primary mt-3" %>
  <% end %>
<% end %>
```

- [ ] **Step 4: Implement the controller action**

In `app/controllers/operator/settings_controller.rb`:

```ruby
def modules
  @operator = current_operator
end

def update_modules
  if current_operator.update(modules_params)
    redirect_to operator_settings_modules_path, notice: "Modules saved."
  else
    render :modules, status: :unprocessable_entity
  end
end

# in private section
def modules_params
  params.require(:operator).permit(
    :announcements_enabled, :events_enabled, :door_integration_enabled,
    :rooms_enabled, :offices_enabled, :bulletin_board_enabled,
    :credits_enabled, :childcare_enabled, :crm_enabled
  )
end
```

- [ ] **Step 5: Run spec to verify it passes**

```
bundle exec rspec spec/requests/operator/settings/modules_spec.rb
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/views/operator/settings/modules.html.erb app/controllers/operator/settings_controller.rb spec/requests/operator/settings/modules_spec.rb
git commit -m "Modules tab: 9 product-module toggles"
```

---

## Task 8: Policies tab (with dollars input)

**Files:**
- Modify: `app/views/operator/settings/policies.html.erb`
- Modify: `app/controllers/operator/settings_controller.rb`
- Create: `spec/requests/operator/settings/policies_spec.rb`

- [ ] **Step 1: Write the failing spec**

`spec/requests/operator/settings/policies_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Operator::Settings Policies", type: :request do
  include OperatorSettingsHelpers
  let(:operator) { sign_in_as_admin }

  it "renders day pass price input in dollars" do
    operator.update!(day_pass_cost_in_cents: 2599)
    get "/operator/settings/policies"
    expect(response.body).to include("name=\"operator[day_pass_cost]\"")
    expect(response.body).to include("25.99")
    expect(response.body).to include("step=\"0.01\"")
  end

  it "saves day pass cost converting dollars to cents" do
    patch "/operator/settings/update_policies", params: {
      operator: { day_pass_cost: "40.99", refund_fee_percent: "5", cancellation_window_hours: "24", renewal_reminder_days: "7", approval_required: "1", checkin_required: "0" }
    }
    expect(response).to redirect_to(operator_settings_policies_path)
    operator.reload
    expect(operator.day_pass_cost_in_cents).to eq(4099)
    expect(operator.refund_fee_percent).to eq(5)
    expect(operator.cancellation_window_hours).to eq(24)
    expect(operator.renewal_reminder_days).to eq(7)
    expect(operator.approval_required).to be true
    expect(operator.checkin_required).to be false
  end

  it "rejects writes directly to day_pass_cost_in_cents" do
    patch "/operator/settings/update_policies", params: {
      operator: { day_pass_cost_in_cents: "1" }
    }
    expect(operator.reload.day_pass_cost_in_cents).not_to eq(1)
  end
end
```

- [ ] **Step 2: Run spec to verify it fails**

```
bundle exec rspec spec/requests/operator/settings/policies_spec.rb
```

Expected: FAIL.

- [ ] **Step 3: Implement the view**

`app/views/operator/settings/policies.html.erb`:

```erb
<%= render layout: "operator/settings/tab_layout", locals: { active: :policies } do %>
  <%= form_with model: current_operator, url: operator_settings_update_policies_path, method: :patch do |f| %>
    <%= render "shared/error_messages", model: current_operator %>

    <div class="form-group">
      <%= f.label :day_pass_cost, "Day pass price" %>
      <div class="input-group">
        <div class="input-group-prepend"><span class="input-group-text">$</span></div>
        <%= f.number_field :day_pass_cost,
                            value: current_operator.day_pass_cost,
                            step: "0.01", min: 0,
                            class: "form-control" %>
      </div>
    </div>

    <div class="form-group">
      <%= f.label :refund_fee_percent, "Refund fee (%)" %>
      <%= f.number_field :refund_fee_percent, min: 0, max: 100, class: "form-control" %>
    </div>

    <div class="form-group">
      <%= f.label :cancellation_window_hours, "Cancellation window (hours)" %>
      <%= f.number_field :cancellation_window_hours, min: 0, class: "form-control" %>
    </div>

    <div class="form-group">
      <%= f.label :renewal_reminder_days, "Renewal reminder (days before)" %>
      <%= f.number_field :renewal_reminder_days, min: 0, class: "form-control" %>
    </div>

    <div class="form-check">
      <%= f.check_box :approval_required, class: "form-check-input" %>
      <%= f.label :approval_required, "New signups require admin approval", class: "form-check-label" %>
    </div>

    <div class="form-check">
      <%= f.check_box :checkin_required, class: "form-check-input" %>
      <%= f.label :checkin_required, "Members must check in to access", class: "form-check-label" %>
    </div>

    <%= f.submit "Save Policies", class: "btn btn-primary mt-3" %>
  <% end %>
<% end %>
```

- [ ] **Step 4: Implement the controller action**

```ruby
def policies
  @operator = current_operator
end

def update_policies
  if current_operator.update(policies_params)
    redirect_to operator_settings_policies_path, notice: "Policies saved."
  else
    render :policies, status: :unprocessable_entity
  end
end

# in private section
def policies_params
  params.require(:operator).permit(
    :day_pass_cost,  # virtual; HasDollars writes to day_pass_cost_in_cents
    :refund_fee_percent,
    :cancellation_window_hours,
    :renewal_reminder_days,
    :approval_required,
    :checkin_required
  )
end
```

- [ ] **Step 5: Run spec to verify it passes**

```
bundle exec rspec spec/requests/operator/settings/policies_spec.rb
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/views/operator/settings/policies.html.erb app/controllers/operator/settings_controller.rb spec/requests/operator/settings/policies_spec.rb
git commit -m "Policies tab: day pass price (dollars) + refund/cancellation/etc."
```

---

## Task 9: In-tab location switcher helper

**Files:**
- Modify: `app/controllers/operator/settings_controller.rb` (add `@selected_location` helper)
- Create: `app/views/operator/settings/_location_switcher.html.erb`

The Payments, Hours & Address, WiFi & Pixels, and Doors tabs need a way to pick which Location they operate on without changing the user's global `current_location`. Pattern: each tab GET reads `params[:location_id]` (falls back to `current_user.current_location`), and the switcher partial submits a `GET` with that param.

- [ ] **Step 1: Write the failing spec**

Append to `spec/requests/operator/settings/skeleton_spec.rb`:

```ruby
context "location switcher" do
  it "uses params[:location_id] when present" do
    other_location = FactoryBot.create(:location, operator: operator)
    get "/operator/settings/hours_and_address", params: { location_id: other_location.id }
    expect(response.body).to include(other_location.name)
  end
end
```

- [ ] **Step 2: Run spec to verify it fails**

```
bundle exec rspec spec/requests/operator/settings/skeleton_spec.rb -e "location switcher"
```

Expected: FAIL (Hours & Address still renders placeholder).

- [ ] **Step 3: Add helper to controller**

In `app/controllers/operator/settings_controller.rb`:

```ruby
private

def selected_location
  @selected_location ||= if params[:location_id].present?
    current_operator.locations.find(params[:location_id])
  else
    current_user.current_location || current_operator.locations.first
  end
end
helper_method :selected_location
```

- [ ] **Step 4: Create the switcher partial**

`app/views/operator/settings/_location_switcher.html.erb`:

```erb
<% if current_operator.locations.count > 1 %>
  <div class="mb-3 d-flex align-items-center">
    <label class="mr-2 text-muted small mb-0">Editing for location:</label>
    <%= form_with url: request.path, method: :get, local: true, class: "d-inline" do %>
      <select name="location_id" class="form-control form-control-sm" onchange="this.form.submit()">
        <% current_operator.locations.order(:name).each do |loc| %>
          <option value="<%= loc.id %>" <%= "selected" if loc.id == selected_location.id %>>
            <%= loc.name %>
          </option>
        <% end %>
      </select>
    <% end %>
  </div>
<% end %>
```

This partial is rendered at the top of each location-scoped tab view (Payments, Doors, Hours & Address, WiFi & Pixels).

- [ ] **Step 5: Wire the switcher into Hours & Address placeholder for the spec**

Modify `app/views/operator/settings/hours_and_address.html.erb` to render selected location name (Task 10 will fully build out the form):

```erb
<%= render layout: "operator/settings/tab_layout", locals: { active: :hours_and_address } do %>
  <%= render "operator/settings/location_switcher" %>
  <p>Editing: <strong><%= selected_location.name %></strong></p>
  <p>Fields coming in Task 10.</p>
<% end %>
```

- [ ] **Step 6: Run spec to verify it passes**

```
bundle exec rspec spec/requests/operator/settings/skeleton_spec.rb -e "location switcher"
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add app/controllers/operator/settings_controller.rb app/views/operator/settings/_location_switcher.html.erb app/views/operator/settings/hours_and_address.html.erb spec/requests/operator/settings/skeleton_spec.rb
git commit -m "Add in-tab location switcher for Settings tabs"
```

---

## Task 10: Hours & Address tab

**Files:**
- Modify: `app/views/operator/settings/hours_and_address.html.erb`
- Modify: `app/controllers/operator/settings_controller.rb`
- Create: `spec/requests/operator/settings/hours_and_address_spec.rb`

- [ ] **Step 1: Write the failing spec**

`spec/requests/operator/settings/hours_and_address_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Operator::Settings Hours & Address", type: :request do
  include OperatorSettingsHelpers
  let(:operator) { sign_in_as_admin }
  let(:location) { operator.locations.first }

  it "renders address and hours fields for the selected location" do
    get "/operator/settings/hours_and_address"
    expect(response).to have_http_status(:ok)
    %w[name building_address city state zip time_zone
       working_day_start working_day_end open_monday open_saturday
       contact_name contact_email contact_phone building_access_instructions
       latitude longitude].each do |attr|
      expect(response.body).to include("location[#{attr}]"), "missing field: #{attr}"
    end
  end

  it "saves address fields" do
    patch "/operator/settings/update_hours_and_address", params: {
      location_id: location.id,
      location: {
        name: "Updated Name", building_address: "1 New St", city: "Tahoe",
        state: "CA", zip: "96150", time_zone: "Pacific Time (US & Canada)",
        working_day_start: "08:00", working_day_end: "20:00",
        open_monday: "1", open_saturday: "0",
        contact_name: "Jane", contact_email: "jane@untethered.com", contact_phone: "555-1234"
      }
    }
    expect(response).to redirect_to(operator_settings_hours_and_address_path(location_id: location.id))
    location.reload
    expect(location.name).to eq("Updated Name")
    expect(location.building_address).to eq("1 New St")
    expect(location.working_day_start).to eq("08:00")
  end
end
```

- [ ] **Step 2: Run spec to verify it fails**

```
bundle exec rspec spec/requests/operator/settings/hours_and_address_spec.rb
```

Expected: FAIL.

- [ ] **Step 3: Implement the view**

Replace `app/views/operator/settings/hours_and_address.html.erb`:

```erb
<%= render layout: "operator/settings/tab_layout", locals: { active: :hours_and_address } do %>
  <%= render "operator/settings/location_switcher" %>

  <%= form_with model: selected_location, url: operator_settings_update_hours_and_address_path(location_id: selected_location.id), method: :patch do |f| %>
    <%= render "shared/error_messages", model: selected_location %>

    <h5>Address</h5>
    <div class="form-group">
      <%= f.label :name, "Location name" %>
      <%= f.text_field :name, class: "form-control" %>
    </div>
    <div class="form-group">
      <%= f.label :building_address %>
      <%= f.text_field :building_address, class: "form-control" %>
    </div>
    <div class="form-row">
      <div class="form-group col-md-6"><%= f.label :city %><%= f.text_field :city, class: "form-control" %></div>
      <div class="form-group col-md-2"><%= f.label :state %><%= f.text_field :state, class: "form-control" %></div>
      <div class="form-group col-md-4"><%= f.label :zip, "ZIP" %><%= f.text_field :zip, class: "form-control" %></div>
    </div>
    <div class="form-row">
      <div class="form-group col-md-6">
        <%= f.label :latitude %>
        <%= f.number_field :latitude, step: "any", class: "form-control" %>
      </div>
      <div class="form-group col-md-6">
        <%= f.label :longitude %>
        <%= f.number_field :longitude, step: "any", class: "form-control" %>
      </div>
    </div>
    <small class="form-text text-muted mb-3">Auto-population from address coming soon.</small>

    <hr>
    <h5>Hours</h5>
    <div class="form-group">
      <%= f.label :time_zone %>
      <%= f.time_zone_select :time_zone, ActiveSupport::TimeZone.us_zones, {}, class: "form-control" %>
    </div>
    <div class="form-row">
      <div class="form-group col-md-6">
        <%= f.label :working_day_start, "Open at" %>
        <%= f.text_field :working_day_start, class: "form-control", placeholder: "09:00" %>
      </div>
      <div class="form-group col-md-6">
        <%= f.label :working_day_end, "Close at" %>
        <%= f.text_field :working_day_end, class: "form-control", placeholder: "18:00" %>
      </div>
    </div>
    <div class="form-group">
      <label>Open days</label>
      <% %i[open_sunday open_monday open_tuesday open_wednesday open_thursday open_friday open_saturday].each do |day| %>
        <div class="form-check form-check-inline">
          <%= f.check_box day, class: "form-check-input" %>
          <%= f.label day, day.to_s.sub("open_", "").titleize, class: "form-check-label" %>
        </div>
      <% end %>
    </div>

    <hr>
    <h5>Building access</h5>
    <div class="form-group">
      <%= f.label :building_access_instructions, "Instructions for members entering the building" %>
      <%= f.text_area :building_access_instructions, rows: 3, class: "form-control" %>
    </div>

    <hr>
    <h5>Contact</h5>
    <div class="form-group">
      <%= f.label :contact_name %>
      <%= f.text_field :contact_name, class: "form-control" %>
    </div>
    <div class="form-group">
      <%= f.label :contact_email %>
      <%= f.email_field :contact_email, class: "form-control" %>
    </div>
    <div class="form-group">
      <%= f.label :contact_phone %>
      <%= f.telephone_field :contact_phone, class: "form-control" %>
    </div>

    <%= f.submit "Save Hours & Address", class: "btn btn-primary" %>
  <% end %>
<% end %>
```

- [ ] **Step 4: Implement the controller action**

```ruby
def hours_and_address
  @location = selected_location
end

def update_hours_and_address
  if selected_location.update(hours_and_address_params)
    redirect_to operator_settings_hours_and_address_path(location_id: selected_location.id), notice: "Hours & address saved."
  else
    render :hours_and_address, status: :unprocessable_entity
  end
end

# in private section
def hours_and_address_params
  params.require(:location).permit(
    :name, :building_address, :city, :state, :zip,
    :latitude, :longitude,
    :time_zone, :working_day_start, :working_day_end,
    :open_sunday, :open_monday, :open_tuesday, :open_wednesday,
    :open_thursday, :open_friday, :open_saturday,
    :building_access_instructions,
    :contact_name, :contact_email, :contact_phone
  )
end
```

- [ ] **Step 5: Run spec to verify it passes**

```
bundle exec rspec spec/requests/operator/settings/hours_and_address_spec.rb
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/views/operator/settings/hours_and_address.html.erb app/controllers/operator/settings_controller.rb spec/requests/operator/settings/hours_and_address_spec.rb
git commit -m "Hours & Address tab: location address + hours + days + contact"
```

---

## Task 11: WiFi & Pixels tab (with nested tracking_pixels)

**Files:**
- Modify: `app/views/operator/settings/wifi_and_pixels.html.erb`
- Modify: `app/controllers/operator/settings_controller.rb`
- Create: `spec/requests/operator/settings/wifi_and_pixels_spec.rb`

- [ ] **Step 1: Write the failing spec**

`spec/requests/operator/settings/wifi_and_pixels_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Operator::Settings WiFi & Pixels", type: :request do
  include OperatorSettingsHelpers
  let(:operator) { sign_in_as_admin }
  let(:location) { operator.locations.first }

  it "renders WiFi fields and existing tracking pixels" do
    location.tracking_pixels.create!(operator: operator, name: "FB Pixel", script: "<script>fbq()</script>")
    get "/operator/settings/wifi_and_pixels"
    expect(response.body).to include("location[wifi_name]")
    expect(response.body).to include("location[wifi_password]")
    expect(response.body).to include("FB Pixel")
  end

  it "saves WiFi credentials" do
    patch "/operator/settings/update_wifi_and_pixels", params: {
      location_id: location.id,
      location: { wifi_name: "Untethered-Guest", wifi_password: "letmein" }
    }
    expect(response).to redirect_to(operator_settings_wifi_and_pixels_path(location_id: location.id))
    location.reload
    expect(location.wifi_name).to eq("Untethered-Guest")
    expect(location.wifi_password).to eq("letmein")
  end

  it "adds a new tracking pixel via nested attributes" do
    patch "/operator/settings/update_wifi_and_pixels", params: {
      location_id: location.id,
      location: {
        tracking_pixels_attributes: [{ name: "GA", script: "<script>gtag()</script>", operator_id: operator.id }]
      }
    }
    expect(location.tracking_pixels.count).to eq(1)
    expect(location.tracking_pixels.first.name).to eq("GA")
  end
end
```

- [ ] **Step 2: Run spec to verify it fails**

```
bundle exec rspec spec/requests/operator/settings/wifi_and_pixels_spec.rb
```

Expected: FAIL.

- [ ] **Step 3: Implement the view**

`app/views/operator/settings/wifi_and_pixels.html.erb`:

```erb
<%= render layout: "operator/settings/tab_layout", locals: { active: :wifi_and_pixels } do %>
  <%= render "operator/settings/location_switcher" %>

  <%= form_with model: selected_location, url: operator_settings_update_wifi_and_pixels_path(location_id: selected_location.id), method: :patch do |f| %>
    <%= render "shared/error_messages", model: selected_location %>

    <h5>WiFi</h5>
    <div class="form-group">
      <%= f.label :wifi_name, "Network name (SSID)" %>
      <%= f.text_field :wifi_name, class: "form-control" %>
    </div>
    <div class="form-group">
      <%= f.label :wifi_password %>
      <%= f.text_field :wifi_password, class: "form-control" %>
    </div>

    <hr>
    <h5>Tracking pixels</h5>
    <p class="text-muted small">JavaScript snippets injected into your public pages (Google Analytics, Facebook Pixel, etc.).</p>

    <div id="tracking_pixels">
      <%= f.fields_for :tracking_pixels do |pixel_form| %>
        <%= render "tracking_pixel_fields", f: pixel_form %>
      <% end %>
    </div>

    <template id="new_tracking_pixel_template">
      <%= f.fields_for :tracking_pixels, TrackingPixel.new(operator: current_operator), child_index: "NEW_RECORD" do |pixel_form| %>
        <%= render "tracking_pixel_fields", f: pixel_form %>
      <% end %>
    </template>

    <button type="button" class="btn btn-sm btn-outline-secondary" onclick="
      const tpl = document.getElementById('new_tracking_pixel_template').innerHTML;
      const html = tpl.replace(/NEW_RECORD/g, new Date().getTime());
      document.getElementById('tracking_pixels').insertAdjacentHTML('beforeend', html);
    ">+ Add tracking pixel</button>

    <hr>
    <%= f.submit "Save WiFi & Pixels", class: "btn btn-primary" %>
  <% end %>
<% end %>
```

Also create the per-pixel fields partial `app/views/operator/settings/_tracking_pixel_fields.html.erb`:

```erb
<div class="card mb-2">
  <div class="card-body">
    <%= f.hidden_field :id %>
    <%= f.hidden_field :operator_id, value: current_operator.id %>
    <div class="form-row">
      <div class="form-group col-md-4">
        <%= f.label :name %>
        <%= f.text_field :name, class: "form-control" %>
      </div>
      <div class="form-group col-md-8">
        <%= f.label :script, "JavaScript snippet" %>
        <%= f.text_area :script, rows: 2, class: "form-control text-monospace" %>
      </div>
    </div>
    <div class="form-check">
      <%= f.check_box :always_on, class: "form-check-input" %>
      <%= f.label :always_on, "Inject even when user hasn't accepted cookies", class: "form-check-label small" %>
    </div>
    <div class="form-check">
      <%= f.check_box :_destroy, class: "form-check-input" %>
      <%= f.label :_destroy, "Delete this pixel", class: "form-check-label small text-danger" %>
    </div>
  </div>
</div>
```

- [ ] **Step 4: Implement the controller action**

```ruby
def wifi_and_pixels
  @location = selected_location
  @location.tracking_pixels.build if @location.tracking_pixels.empty?
end

def update_wifi_and_pixels
  if selected_location.update(wifi_and_pixels_params)
    redirect_to operator_settings_wifi_and_pixels_path(location_id: selected_location.id), notice: "WiFi & pixels saved."
  else
    render :wifi_and_pixels, status: :unprocessable_entity
  end
end

# in private section
def wifi_and_pixels_params
  params.require(:location).permit(
    :wifi_name, :wifi_password,
    tracking_pixels_attributes: [:id, :operator_id, :name, :script, :always_on, :_destroy]
  )
end
```

- [ ] **Step 5: Run spec to verify it passes**

```
bundle exec rspec spec/requests/operator/settings/wifi_and_pixels_spec.rb
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/views/operator/settings/wifi_and_pixels.html.erb app/views/operator/settings/_tracking_pixel_fields.html.erb app/controllers/operator/settings_controller.rb spec/requests/operator/settings/wifi_and_pixels_spec.rb
git commit -m "WiFi & Pixels tab: location WiFi + nested tracking_pixels"
```

---

## Task 12: Payments tab (status panel + reuse OAuth modal)

**Files:**
- Modify: `app/views/operator/settings/payments.html.erb`
- Modify: `app/controllers/operator/settings_controller.rb` (real `payments`)
- Create: `spec/requests/operator/settings/payments_spec.rb`

- [ ] **Step 1: Write the failing spec**

`spec/requests/operator/settings/payments_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Operator::Settings Payments", type: :request do
  include OperatorSettingsHelpers
  let(:operator) { sign_in_as_admin }
  let(:location) { operator.locations.first }

  context "when location is connected to Stripe" do
    before { location.update!(stripe_user_id: "acct_test1234", stripe_access_token: "sk_test_xxx", stripe_publishable_key: "pk_test_abcd1234") }

    it "renders Connected status with last chars of account id" do
      get "/operator/settings/payments"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Stripe Connected")
      expect(response.body).to include("acct_test1234".last(4)).or include("1234")
      expect(response.body).to include("Reconnect")
    end
  end

  context "when location is not connected" do
    before { location.update!(stripe_user_id: nil, stripe_access_token: nil) }

    it "renders Not Connected status and Connect button" do
      get "/operator/settings/payments"
      expect(response.body).to include("Stripe Not Connected")
      expect(response.body).to include("Connect Stripe")
    end
  end

  it "has no patch route — Stripe Connect handled by OAuth" do
    expect { patch "/operator/settings/update_payments" }.to raise_error(ActionController::RoutingError).or change { response&.status }.to(404)
  end
end
```

- [ ] **Step 2: Run spec to verify it fails**

```
bundle exec rspec spec/requests/operator/settings/payments_spec.rb
```

Expected: FAIL on the "Connected" assertions.

- [ ] **Step 3: Implement the view**

`app/views/operator/settings/payments.html.erb`:

```erb
<%= render layout: "operator/settings/tab_layout", locals: { active: :payments } do %>
  <%= render "operator/settings/location_switcher" %>

  <% connected = selected_location.stripe_user_id.present? && selected_location.stripe_access_token.present? %>

  <div class="card">
    <div class="card-body">
      <% if connected %>
        <h4 class="text-success"><span class="fas fa-circle"></span> Stripe Connected</h4>
        <dl class="row mb-3 small">
          <dt class="col-sm-3">Account</dt>
          <dd class="col-sm-9 text-monospace">acct_••••<%= selected_location.stripe_user_id.to_s.last(4) %></dd>
          <dt class="col-sm-3">Publishable key</dt>
          <dd class="col-sm-9 text-monospace">pk_••••<%= selected_location.stripe_publishable_key.to_s.last(4) %></dd>
        </dl>
        <button type="button" class="btn btn-outline-primary" data-toggle="modal" data-target="#stripeModal">
          Reconnect Stripe Account
        </button>
      <% else %>
        <h4 class="text-muted"><span class="far fa-circle"></span> Stripe Not Connected</h4>
        <p>You'll need a Stripe account to accept day passes, memberships, and room reservations.</p>
        <button type="button" class="btn btn-primary" data-toggle="modal" data-target="#stripeModal">
          Connect Stripe Account
        </button>
      <% end %>
    </div>
  </div>

  <%= render "shared/stripe_connect_modal" %>
<% end %>
```

- [ ] **Step 4: Implement the controller GET action**

In `app/controllers/operator/settings_controller.rb`:

```ruby
def payments
  @location = selected_location
end
```

(No update action — payments has no PATCH.)

- [ ] **Step 5: Run spec to verify it passes**

```
bundle exec rspec spec/requests/operator/settings/payments_spec.rb
```

Expected: connected/not-connected examples PASS. The "no patch route" example may need adjustment depending on how Rails routing errors surface in request specs — change to `expect(response).to have_http_status(:not_found)` if needed, or remove the example.

- [ ] **Step 6: Commit**

```bash
git add app/views/operator/settings/payments.html.erb app/controllers/operator/settings_controller.rb spec/requests/operator/settings/payments_spec.rb
git commit -m "Payments tab: Stripe Connect status panel + reuse OAuth modal"
```

---

## Task 13: Redirect Stripe OAuth callback to /operator/settings/payments

**Files:**
- Modify: wherever `Operators::FinishStripeConnect` (or its caller) issues its post-OAuth redirect. Likely `app/controllers/operator/operators_controller.rb#stripe_connect_setup` or a Stripe Connect callback action.

- [ ] **Step 1: Locate the redirect**

```
rg -n "customization_path|redirect_to.*customization|redirect_to.*modules" app/controllers app/interactors 2>/dev/null
```

Find the post-OAuth redirect (usually 1–2 lines). Note the file and line.

- [ ] **Step 2: Change the target**

Replace `customization_path` (or whatever the current target is) with `operator_settings_payments_path` in that callback.

Example (if it lives in `app/controllers/operator/operators_controller.rb`):

```ruby
def stripe_connect_setup
  # ... existing OAuth code ...
  if result.success?
    redirect_to operator_settings_payments_path, notice: "Stripe connected!"
  else
    redirect_to operator_settings_payments_path, alert: "Stripe connection failed: #{result.message}"
  end
end
```

- [ ] **Step 3: Manually verify by hitting the OAuth flow locally**

Hard to write an automated test for OAuth callback. Manual smoke:
- Boot server, sign in as an operator without Stripe connected
- Visit `/operator/settings/payments` → Connect button
- Complete OAuth (use Stripe test mode)
- Confirm you land back on `/operator/settings/payments` with success flash

If the OAuth flow can't be tested locally, defer to the next deploy with a note in the commit.

- [ ] **Step 4: Commit**

```bash
git add <the-file-you-changed>
git commit -m "Redirect Stripe OAuth callback to /operator/settings/payments"
```

---

## Task 14: Doors tab — operator KISI key + per-location overrides + import

**Files:**
- Modify: `app/views/operator/settings/doors.html.erb`
- Modify: `app/controllers/operator/settings_controller.rb`
- Create: `spec/requests/operator/settings/doors_spec.rb`

- [ ] **Step 1: Write the failing spec**

`spec/requests/operator/settings/doors_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Operator::Settings Doors", type: :request do
  include OperatorSettingsHelpers
  let(:operator) { sign_in_as_admin }
  let(:location) { operator.locations.first }

  it "renders operator-level KISI key + per-location overrides + import button" do
    operator.update!(kisi_api_key: "operator-key-xyz")
    location.update!(kisi_api_key: nil)
    get "/operator/settings/doors"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("operator[kisi_api_key]")
    expect(response.body).to include(location.name)
    expect(response.body).to include("uses operator default")
    expect(response.body).to include("Import doors from KISI")
  end

  it "saves operator-level KISI key" do
    patch "/operator/settings/update_doors", params: {
      operator: { kisi_api_key: "new-operator-key" }
    }
    expect(response).to redirect_to(operator_settings_doors_path)
    expect(operator.reload.kisi_api_key).to eq("new-operator-key")
  end

  it "saves per-location override and clears it back to default" do
    patch "/operator/settings/update_doors", params: {
      operator: { locations_attributes: [{ id: location.id, kisi_api_key: "loc-override" }] }
    }
    expect(location.reload.kisi_api_key).to eq("loc-override")

    patch "/operator/settings/update_doors", params: {
      operator: { locations_attributes: [{ id: location.id, kisi_api_key: "" }] }
    }
    expect(location.reload.kisi_api_key).to be_nil
  end

  it "import_doors calls Onboarding::GetKisiDoors" do
    expect(Onboarding::GetKisiDoors).to receive(:run!).with(hash_including(location: location)).and_return(double(success?: true))
    post "/operator/settings/import_doors", params: { location_id: location.id }
    expect(response).to redirect_to(operator_settings_doors_path(location_id: location.id))
  end
end
```

- [ ] **Step 2: Run spec to verify it fails**

```
bundle exec rspec spec/requests/operator/settings/doors_spec.rb
```

Expected: FAIL.

- [ ] **Step 3: Allow nested Locations on Operator**

In `app/models/operator.rb`, add (if not already present):

```ruby
accepts_nested_attributes_for :locations, allow_destroy: false
```

- [ ] **Step 4: Implement the view**

`app/views/operator/settings/doors.html.erb`:

```erb
<%= render layout: "operator/settings/tab_layout", locals: { active: :doors } do %>
  <h5>KISI API key</h5>
  <%= form_with model: current_operator, url: operator_settings_update_doors_path, method: :patch do |f| %>
    <div class="form-group">
      <%= f.label :kisi_api_key, "Operator-wide KISI API key (used as default for all locations)" %>
      <%= f.text_field :kisi_api_key, class: "form-control text-monospace" %>
      <small class="form-text text-muted">Locations without their own override use this key.</small>
    </div>

    <% if current_operator.locations.count > 1 %>
      <h6 class="mt-4">Per-location overrides</h6>
      <%= f.fields_for :locations, current_operator.locations.order(:name) do |loc_form| %>
        <div class="form-row align-items-end mb-2">
          <%= loc_form.hidden_field :id %>
          <div class="col-md-4"><%= loc_form.object.name %></div>
          <div class="col-md-6">
            <%= loc_form.text_field :kisi_api_key,
                                    placeholder: loc_form.object.kisi_api_key.nil? ? "uses operator default" : "kisi_••••#{loc_form.object.kisi_api_key.to_s.last(4)}",
                                    class: "form-control text-monospace form-control-sm" %>
          </div>
          <div class="col-md-2">
            <% if loc_form.object.kisi_api_key.nil? %>
              <span class="badge badge-secondary">uses operator default</span>
            <% else %>
              <span class="badge badge-info">override</span>
            <% end %>
          </div>
        </div>
      <% end %>
    <% end %>

    <%= f.submit "Save KISI key", class: "btn btn-primary" %>
  <% end %>

  <hr class="my-4">

  <h5>Doors</h5>
  <%= form_with url: operator_settings_import_doors_path, method: :post, local: true, class: "form-inline mb-3" do %>
    <% if current_operator.locations.count > 1 %>
      <select name="location_id" class="form-control mr-2">
        <% current_operator.locations.order(:name).each do |loc| %>
          <option value="<%= loc.id %>" <%= "selected" if loc.id == selected_location.id %>><%= loc.name %></option>
        <% end %>
      </select>
    <% else %>
      <%= hidden_field_tag :location_id, current_operator.locations.first.id %>
    <% end %>
    <button type="submit" class="btn btn-outline-primary">
      <i class="fas fa-cloud-download-alt mr-1"></i> Import doors from KISI
    </button>
  <% end %>

  <%= turbo_frame_tag "doors_list", src: doors_path(location_id: selected_location.id) %>
<% end %>
```

- [ ] **Step 5: Implement the controller actions**

```ruby
def doors
  @operator = current_operator
end

def update_doors
  if current_operator.update(doors_params)
    redirect_to operator_settings_doors_path, notice: "Doors settings saved."
  else
    render :doors, status: :unprocessable_entity
  end
end

def import_doors
  result = Onboarding::GetKisiDoors.run!(location: selected_location)
  if result.success?
    redirect_to operator_settings_doors_path(location_id: selected_location.id), notice: "Doors imported from KISI."
  else
    redirect_to operator_settings_doors_path(location_id: selected_location.id), alert: "KISI import failed: #{result.message}"
  end
rescue => e
  redirect_to operator_settings_doors_path(location_id: selected_location.id), alert: "KISI import error: #{e.message}"
end

# in private section
def doors_params
  params.require(:operator).permit(
    :kisi_api_key,
    locations_attributes: [:id, :kisi_api_key]
  )
end
```

(Verify `Onboarding::GetKisiDoors.run!` signature matches the interactor — adjust call if needed. If it's an Interactor-gem class, it might use `.call(location: …)` instead of `.run!`.)

- [ ] **Step 6: Run spec to verify it passes**

```
bundle exec rspec spec/requests/operator/settings/doors_spec.rb
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add app/views/operator/settings/doors.html.erb app/controllers/operator/settings_controller.rb app/models/operator.rb spec/requests/operator/settings/doors_spec.rb
git commit -m "Doors tab: operator KISI key + per-location overrides + KISI import"
```

---

## Task 15: Wrap Operator::DoorsController#index view in Turbo Frame

**Files:**
- Modify: `app/views/operator/doors/index.html.erb`

The Doors tab embeds the door list as a `<turbo-frame id="doors_list">`. The frame matches when the embedded page's response includes a `<turbo-frame id="doors_list">` tag. So we wrap the existing door list content.

- [ ] **Step 1: Inspect the existing view**

```
cat app/views/operator/doors/index.html.erb
```

- [ ] **Step 2: Wrap the content in a Turbo Frame**

Edit `app/views/operator/doors/index.html.erb` — wrap the existing content (everything that's currently inside the file):

```erb
<%= turbo_frame_tag "doors_list" do %>
  <%# ...existing index content unchanged... %>
<% end %>
```

(If the existing view has a heading/breadcrumb at the top, leave it OUTSIDE the frame so standalone `/doors` page navigation still has its title. Only wrap the list itself.)

- [ ] **Step 3: Manually verify both paths**

```
bin/rails server
```

- Visit `http://localhost:3000/doors` directly → still works as a standalone page
- Visit `http://localhost:3000/operator/settings/doors` → see embedded door list at bottom

- [ ] **Step 4: Commit**

```bash
git add app/views/operator/doors/index.html.erb
git commit -m "Wrap operator doors index in turbo_frame_tag for embedding"
```

---

## Task 16: Legacy redirects (`/customization` + `/operator/operators/:id/edit`)

**Files:**
- Modify: `config/routes.rb`
- Modify: `app/controllers/operator/settings_controller.rb` (add `legacy_redirect`)
- Create: `spec/requests/operator/settings/legacy_redirects_spec.rb`

- [ ] **Step 1: Write the failing spec**

`spec/requests/operator/settings/legacy_redirects_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Operator::Settings legacy redirects", type: :request do
  include OperatorSettingsHelpers
  let(:operator) { sign_in_as_admin }

  it "GET /customization → 301 → /operator/settings/branding" do
    get "/customization"
    expect(response).to have_http_status(:moved_permanently)
    expect(response).to redirect_to("/operator/settings/branding")
  end

  it "GET /operator/operators/:id/edit → 301 → /operator/settings/branding" do
    get "/operator/operators/#{operator.id}/edit"
    expect(response).to have_http_status(:moved_permanently)
    expect(response).to redirect_to("/operator/settings/branding")
  end
end
```

- [ ] **Step 2: Run spec to verify it fails**

```
bundle exec rspec spec/requests/operator/settings/legacy_redirects_spec.rb
```

Expected: FAIL — `/customization` still routes to `LandingController#customization`.

- [ ] **Step 3: Add the redirect action**

In `app/controllers/operator/settings_controller.rb`:

```ruby
def legacy_redirect
  redirect_to operator_settings_branding_path, status: :moved_permanently
end
```

- [ ] **Step 4: Update routes**

In `config/routes.rb`:

- Find the line `get :customization, to: "landing#customization"` (or similar) and **comment it out** (will be deleted in Task 19).
- At the bottom of the routes (or near the settings resource), add:

```ruby
get "/customization", to: "operator/settings#legacy_redirect"
get "/operator/operators/:id/edit", to: "operator/settings#legacy_redirect"
```

Note: routes are matched top-down — these need to come AFTER the `resource :settings` block but BEFORE any catch-all route.

- [ ] **Step 5: Run spec to verify it passes**

```
bundle exec rspec spec/requests/operator/settings/legacy_redirects_spec.rb
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add config/routes.rb app/controllers/operator/settings_controller.rb spec/requests/operator/settings/legacy_redirects_spec.rb
git commit -m "301 redirect /customization and operator-edit → /operator/settings/branding"
```

---

## Task 17: Replace operator nav Customization+App Config entries with Settings

**Files:**
- Modify: `app/adapters/navigation/default.rb`

- [ ] **Step 1: Read the nav file to find the exact lines**

```
cat app/adapters/navigation/default.rb
```

Locate lines 66 (Customization), 82 (App Config), and 180 (likely a duplicate Customization).

- [ ] **Step 2: Replace Customization with Settings, drop App Config**

Edit `app/adapters/navigation/default.rb`:

- Line ~66: change `{title: "Customization", path: customization_path},` to:
  ```ruby
  {title: "Settings", path: operator_settings_branding_path},
  ```
- Line ~82: delete the entire `items << {title: "App Config", path: app_configs_path}` line.
- Line ~180: same replacement as line 66.

Also update `app/views/layouts/_admin_nav.html.erb` line 26 (the `settings_titles` array used to group the dropdown):

```ruby
settings_titles = ["Settings", "Change Location", "My Account", "Member Dashboard"]
```

And line 20–24 (nav_icons hash): change `"Customization" => "fas fa-paint-brush",` to `"Settings" => "fas fa-cog",` and **delete** `"App Config" => "fas fa-cog",`.

- [ ] **Step 3: Manually verify in browser**

```
bin/rails server
```

Sign in as admin → confirm nav shows "Settings" linking to `/operator/settings/branding` and "Customization" and "App Config" entries are gone.

- [ ] **Step 4: Commit**

```bash
git add app/adapters/navigation/default.rb app/views/layouts/_admin_nav.html.erb
git commit -m "Replace Customization + App Config nav entries with Settings"
```

---

## Task 18: Gate /app_configs behind superadmin

**Files:**
- Modify: `app/controllers/operator/app_configs_controller.rb`
- Create: `spec/requests/operator/app_configs_gating_spec.rb`

- [ ] **Step 1: Write the failing spec**

`spec/requests/operator/app_configs_gating_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Operator::AppConfigsController gating", type: :request do
  include OperatorSettingsHelpers

  it "regular admin gets redirected/forbidden" do
    sign_in_as_admin
    get "/app_configs"
    expect(response.status).to be_in([302, 403])
  end

  it "superadmin gets through" do
    operator = Operator.find_by(subdomain: "untethered") || FactoryBot.create(:operator, subdomain: "untethered")
    location = operator.locations.first || FactoryBot.create(:location, operator: operator)
    superadmin = FactoryBot.create(:user, :superadmin, operator: operator, current_location: location)
    ActsAsTenant.current_tenant = operator
    host! "untethered.example.com"
    post "/session", params: { session: { email: superadmin.email, password: "password" } }
    get "/app_configs"
    expect(response).to have_http_status(:ok)
  end
end
```

(If the user factory doesn't have a `:superadmin` trait, add one: `trait(:superadmin) { superadmin true }`.)

- [ ] **Step 2: Run spec to verify it fails**

```
bundle exec rspec spec/requests/operator/app_configs_gating_spec.rb
```

Expected: regular admin currently has access — FAIL.

- [ ] **Step 3: Add the before_action**

In `app/controllers/operator/app_configs_controller.rb`, near the top of the class body:

```ruby
before_action :require_superadmin!

private

def require_superadmin!
  redirect_to root_path, alert: "Superadmin only." unless current_user&.superadmin?
end
```

(Keep the existing actions intact.)

- [ ] **Step 4: Run spec to verify it passes**

```
bundle exec rspec spec/requests/operator/app_configs_gating_spec.rb
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/operator/app_configs_controller.rb spec/requests/operator/app_configs_gating_spec.rb
git commit -m "Gate /app_configs behind superadmin?"
```

---

## Task 19: Remove Stripe Connect trigger from Modules page

**Files:**
- Modify: `app/views/operator/modules/index.html.erb`

The Modules page currently launches the Stripe Connect modal (lines 23–43 per earlier inventory). Now that Payments lives in Settings, remove that trigger.

- [ ] **Step 1: Inspect current state**

```
sed -n '15,55p' app/views/operator/modules/index.html.erb
```

Identify the block that includes the `data-target="#stripeModal"` trigger.

- [ ] **Step 2: Remove the Stripe modal trigger block**

Replace the Stripe-trigger block with a small notice linking to Settings → Payments. Example:

```erb
<% if !policy(:payment).enabled? %>
  <div class="alert alert-info">
    Set up payments in <%= link_to "Settings → Payments", operator_settings_payments_path %> to enable membership and reservation modules.
  </div>
<% end %>
```

(Remove the entire `<button data-toggle="modal" data-target="#stripeModal">` and any `<%= render "shared/stripe_connect_modal" %>` rendering on that page.)

- [ ] **Step 3: Manually verify**

```
bin/rails server
```

Visit `/modules` → confirm Stripe Connect button is gone, info alert links to `/operator/settings/payments`.

- [ ] **Step 4: Commit**

```bash
git add app/views/operator/modules/index.html.erb
git commit -m "Remove Stripe Connect trigger from /modules; link to Settings instead"
```

---

## Task 20: Delete old operator-edit and customization views/actions

**Files:**
- Delete: `app/views/operator/operators/edit.html.erb`
- Delete: `app/views/operator/operators/_form.html.erb` (only if not used elsewhere — verify with grep)
- Delete: `app/views/operator/landing/customization.html.erb`
- Modify: `app/controllers/operator/operators_controller.rb` (remove `#edit` + `#update`; keep `#stripe_connect_setup` and others)
- Modify: `app/controllers/landing_controller.rb` (remove `#customization`)
- Modify: `config/routes.rb` (remove the old `get :customization, to: "landing#customization"` and any `resources :operators` lines that route to deleted edit/update actions)

- [ ] **Step 1: Verify _form.html.erb is not used elsewhere**

```
rg "operator/operators/form" app/views app/controllers
```

If results found: leave `_form.html.erb` alone. If empty: safe to delete.

- [ ] **Step 2: Delete the view files**

```bash
git rm app/views/operator/operators/edit.html.erb
git rm app/views/operator/landing/customization.html.erb
# Conditionally:
# git rm app/views/operator/operators/_form.html.erb
```

- [ ] **Step 3: Remove the controller actions**

In `app/controllers/operator/operators_controller.rb`, delete `def edit ... end` and `def update ... end` blocks. KEEP `def stripe_connect_setup` and any other actions.

In `app/controllers/landing_controller.rb`, delete `def customization ... end`.

- [ ] **Step 4: Remove the old routes**

In `config/routes.rb`:
- Find any `resources :operators` line inside `namespace :operator do` that declares `[:edit, :update]` and either remove the line or change to `only: [...]` excluding edit/update.
- Find the line `get :customization, to: "landing#customization"` (or `get "/customization", to: "landing#customization"`) and remove it. The legacy redirect added in Task 16 stays.

- [ ] **Step 5: Run the full request spec suite**

```
bundle exec rspec spec/requests/operator/settings/
bundle exec rspec spec/requests/operator/
```

Expected: green. If any other spec depended on `#edit`/`#update` or `#customization`, fix the callers or skip with explanation.

- [ ] **Step 6: Commit**

```bash
git add -u app/views/operator/ app/controllers/operator/operators_controller.rb app/controllers/landing_controller.rb config/routes.rb
git commit -m "Delete operator-edit and customization views/actions/routes"
```

---

## Task 21: System test — tab navigation + save flow

**Files:**
- Create: `test/system/operator/settings_navigation_test.rb`

- [ ] **Step 1: Write the system test**

`test/system/operator/settings_navigation_test.rb`:

```ruby
require "application_system_test_case"

class Operator::SettingsNavigationTest < ApplicationSystemTestCase
  setup do
    @operator = operators(:untethered)
    @location = locations(:untethered_main)
    @admin = users(:untethered_admin)  # adjust fixture names to match the suite
    ActsAsTenant.current_tenant = @operator
    sign_in @admin  # use whatever sign-in helper system tests already use
  end

  test "lands on branding tab from /operator/settings" do
    visit "/operator/settings"
    assert_current_path "/operator/settings/branding"
    assert_text "Branding & Content"
  end

  test "navigates through Doors, Notifications, back to Branding without JS errors" do
    visit "/operator/settings/branding"
    click_on "Doors"
    assert_current_path %r{/operator/settings/doors}
    click_on "Notifications"
    assert_current_path %r{/operator/settings/notifications}
    click_on "Branding & Content"
    assert_current_path %r{/operator/settings/branding}
  end

  test "saves a branding field" do
    visit "/operator/settings/branding"
    fill_in "operator[snippet]", with: "Edited via system test"
    click_on "Save Branding"
    assert_text "Branding saved"
    assert_equal "Edited via system test", @operator.reload.snippet
  end
end
```

(Fixture names and `sign_in` helper need to match the existing system test conventions in this repo. Copy patterns from any existing test under `test/system/operator/`.)

- [ ] **Step 2: Run the system test**

```
bin/rails test test/system/operator/settings_navigation_test.rb
```

Expected: all 3 tests PASS.

- [ ] **Step 3: Commit**

```bash
git add test/system/operator/settings_navigation_test.rb
git commit -m "System test: Operator Settings tab navigation + branding save"
```

---

## Task 22: Final verification + smoke test

- [ ] **Step 1: Run full Minitest suite**

```
bin/rails test
```

Expected: green. If anything is red, do NOT mark this task complete — diagnose, fix, then re-run.

- [ ] **Step 2: Run full RSpec suite**

```
bundle exec rspec
```

Expected: green. Same gate.

- [ ] **Step 3: Boot the app locally and click through all 8 tabs**

```
bin/rails server
```

For each tab (Branding, Payments, Doors, Hours & Address, WiFi & Pixels, Notifications, Modules, Policies):
- Visit the tab via the sidebar.
- Save at least one field.
- Reload and confirm the change persisted (or, for Payments, confirm the OAuth modal opens).
- Check browser console for JS errors.

- [ ] **Step 4: Verify the 301 redirects manually**

```
curl -sI http://localhost:3000/customization
curl -sI http://localhost:3000/operator/operators/1/edit
```

Expected: both return `301 Moved Permanently` with `Location: /operator/settings/branding`.

- [ ] **Step 5: Verify /app_configs is gated**

Sign in as a non-superadmin → visit `/app_configs` → expect redirect/forbidden.
Sign in as a superadmin → visit `/app_configs` → expect 200.

- [ ] **Step 6: Final commit if any cleanup**

If you found anything that needed polish during smoke testing (typos, missing `notice` flash messages, broken icons), fix and commit:

```bash
git add -u
git commit -m "Polish: <what you fixed>"
```

Otherwise no final commit needed.

- [ ] **Step 7: Push the branch**

```bash
git push origin claude/zealous-montalcini-af4f45
```

---

## Out of Scope (Reminder)

These are NOT in this PR — each is its own sub-project per [project_setup_flow_inventory](../../../.claude/projects/-Users-DavidOrr-Downloads-new-jellyswitch/memory/project_setup_flow_inventory.md):

- **Sub-project B** — Add Stripe Connect step to onboarding wizard
- **Sub-project C** — Smart signup geolocation (auto-pick closest Location)
- **Sub-project 2** — Mobile Stripe + KISI surfaces (`AdminSettingsScreen` parity)
- **Sub-project D** — Mobile UI polish + Maestro regression
- **Sub-project E** — TestFlight build + submission

After this PR is merged, the next session should pick the next sub-project from the inventory.
