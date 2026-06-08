# Brand Collection (Backend) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Capture brand **colors** + a square **app-icon** during operator onboarding, and expose them (with everything the mobile scaffolder needs) at `GET /api/v1/brand_spec`.

**Architecture:** Add two color columns + an `app_icon_image` attachment to `Operator`; extend the onboarding Branding step to collect them; assemble the canonical brand-spec in a `BrandSpec::Build` interactor; serve it from a token-authenticated API controller that resolves the operator by `X-Operator-Subdomain`.

**Tech Stack:** Rails 7.2, Active Storage, ActsAsTenant, `interactor` gem, Minitest (`ActionDispatch::IntegrationTest`, fixtures, `log_in` helper).

**Spec:** `~/Downloads/jellyswitch-mobile/docs/superpowers/specs/2026-06-07-brand-collection-backend-design.md` (piece 2 of 3). The brand-spec JSON contract is in that repo's `…-pipeline-overview.md`.

Run all commands from the repo root: `~/Downloads/new-jellyswitch`. Test command: `bin/rails test <file>`.

---

## File structure

| File | Responsibility |
|------|----------------|
| `db/migrate/<ts>_add_brand_colors_to_operators.rb` | add `primary_color`, `accent_color` string columns |
| `app/models/operator.rb` | `has_one_attached :app_icon_image` + hex color validations |
| `app/interactors/brand_spec/build.rb` | operator (+ asset URLs) → canonical brand-spec hash |
| `app/controllers/operator/onboarding_controller.rb` | permit colors + app-icon; gate branding completeness |
| `app/views/operator/onboarding/new_branding.html.erb` | color inputs + app-icon upload |
| `app/controllers/api/v1/brand_specs_controller.rb` | token-auth endpoint, resolves operator by subdomain |
| `config/routes.rb` | `get 'brand_spec'` route |
| `test/fixtures/files/app_icon.png` | tiny PNG for upload tests |
| `test/models/operator_test.rb` | color validation tests |
| `test/interactors/brand_spec/build_test.rb` | interactor test |
| `test/controllers/operator/onboarding_branding_test.rb` | branding-step integration test |
| `test/controllers/api/v1/brand_specs_controller_test.rb` | endpoint request test |

Canonical brand-spec the interactor produces (must match the mobile engine's consumer):
```ruby
# { key:, name:, subdomain:, apiBase:,
#   bundleId: { ios:, android: },
#   colors: { primary:, accent: },
#   splashBackground:, assets: { appIcon:, wordmark: } }
```

---

## Task 1: Migration + model (colors, app-icon, validations)

**Files:**
- Create: `db/migrate/<ts>_add_brand_colors_to_operators.rb` (via generator)
- Modify: `app/models/operator.rb`
- Test: `test/models/operator_test.rb`

- [ ] **Step 1: Generate the migration**

Run: `bin/rails g migration AddBrandColorsToOperators primary_color:string accent_color:string`
Expected: creates `db/migrate/<timestamp>_add_brand_colors_to_operators.rb` containing:
```ruby
class AddBrandColorsToOperators < ActiveRecord::Migration[7.2]
  def change
    add_column :operators, :primary_color, :string
    add_column :operators, :accent_color, :string
  end
end
```

- [ ] **Step 2: Migrate**

Run: `bin/rails db:migrate`
Expected: schema updated; `db/schema.rb` shows the two new columns on `operators`.

- [ ] **Step 3: Write the failing model tests**

Add to `test/models/operator_test.rb` inside the test class:
```ruby
  test "accepts valid hex brand colors" do
    op = operators(:cowork_tahoe)
    op.primary_color = "#436541"
    op.accent_color = "#C9A23A"
    assert op.valid?, op.errors.full_messages.to_sentence
  end

  test "rejects malformed hex brand colors" do
    op = operators(:cowork_tahoe)
    op.primary_color = "not-a-color"
    refute op.valid?
    assert_includes op.errors[:primary_color], "is invalid"
  end

  test "allows blank brand colors (legacy operators)" do
    op = operators(:cowork_tahoe)
    op.primary_color = nil
    op.accent_color = ""
    assert op.valid?, op.errors.full_messages.to_sentence
  end

  test "app_icon_image can be attached" do
    op = operators(:cowork_tahoe)
    op.app_icon_image.attach(
      io: File.open(Rails.root.join("test/fixtures/files/app_icon.png")),
      filename: "app_icon.png", content_type: "image/png"
    )
    assert op.app_icon_image.attached?
  end
```

- [ ] **Step 4: Create the PNG fixture the test needs**

Run:
```bash
mkdir -p test/fixtures/files
printf 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==' | base64 --decode > test/fixtures/files/app_icon.png
```
Expected: a 1×1 PNG exists at `test/fixtures/files/app_icon.png` (`file` reports "PNG image data").

- [ ] **Step 5: Run tests to verify they fail**

Run: `bin/rails test test/models/operator_test.rb`
Expected: FAIL — the color tests fail (no validation yet → malformed color is "valid"), and `app_icon_image` raises NoMethodError.

- [ ] **Step 6: Implement the model changes**

In `app/models/operator.rb`, add next to the other `has_one_attached` lines (near line 130):
```ruby
  has_one_attached :app_icon_image
```
And add, near the other `validates` declarations:
```ruby
  BRAND_HEX_COLOR = /\A#?[0-9a-fA-F]{6}\z/
  validates :primary_color, format: { with: BRAND_HEX_COLOR }, allow_blank: true
  validates :accent_color, format: { with: BRAND_HEX_COLOR }, allow_blank: true
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `bin/rails test test/models/operator_test.rb`
Expected: PASS (all operator model tests).

- [ ] **Step 8: Commit**

```bash
git add db/migrate db/schema.rb app/models/operator.rb test/models/operator_test.rb test/fixtures/files/app_icon.png
git commit -m "feat(operator): brand colors + app_icon attachment with hex validation"
```

---

## Task 2: BrandSpec::Build interactor

**Files:**
- Create: `app/interactors/brand_spec/build.rb`
- Test: `test/interactors/brand_spec/build_test.rb`

- [ ] **Step 1: Write the failing test**

Create `test/interactors/brand_spec/build_test.rb`:
```ruby
require "test_helper"

class BrandSpec::BuildTest < ActiveSupport::TestCase
  test "assembles the canonical brand-spec from an operator" do
    op = operators(:cowork_tahoe)
    op.update!(primary_color: "#76B82A", accent_color: "#E8871E")

    result = BrandSpec::Build.call(
      operator: op,
      app_icon_url: "https://cdn.example/app_icon.png",
      wordmark_url: nil
    )

    assert result.success?
    spec = result.brand_spec
    assert_equal op.subdomain.parameterize, spec[:key]
    assert_equal op.name, spec[:name]
    assert_equal op.subdomain, spec[:subdomain]
    assert_equal "https://#{op.subdomain}.jellyswitch.com/api/v1", spec[:apiBase]
    expected_bundle = "com.jellyswitch.#{op.subdomain.parameterize.delete('-')}"
    assert_equal expected_bundle, spec[:bundleId][:ios]
    assert_equal expected_bundle, spec[:bundleId][:android]
    assert_equal "#76B82A", spec[:colors][:primary]
    assert_equal "#E8871E", spec[:colors][:accent]
    assert_equal "#FFFFFF", spec[:splashBackground]
    assert_equal "https://cdn.example/app_icon.png", spec[:assets][:appIcon]
    assert_nil spec[:assets][:wordmark]
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `bin/rails test test/interactors/brand_spec/build_test.rb`
Expected: FAIL — `uninitialized constant BrandSpec`.

- [ ] **Step 3: Implement the interactor**

Create `app/interactors/brand_spec/build.rb`:
```ruby
module BrandSpec
  # Operator (+ already-resolved asset URLs) -> canonical brand-spec hash.
  # URLs are passed in because Active Storage URL generation needs the request
  # host, which lives in the controller (or the CI job), not here.
  class Build
    include Interactor

    delegate :operator, :app_icon_url, :wordmark_url, to: :context

    def call
      op = operator
      key = op.subdomain.parameterize
      bundle = "com.jellyswitch.#{key.delete('-')}"

      context.brand_spec = {
        key: key,
        name: op.name,
        subdomain: op.subdomain,
        apiBase: "https://#{op.subdomain}.jellyswitch.com/api/v1",
        bundleId: { ios: bundle, android: bundle },
        colors: { primary: op.primary_color, accent: op.accent_color },
        splashBackground: "#FFFFFF",
        assets: { appIcon: app_icon_url, wordmark: wordmark_url }
      }
    end
  end
end
```

- [ ] **Step 4: Run to verify it passes**

Run: `bin/rails test test/interactors/brand_spec/build_test.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/interactors/brand_spec/build.rb test/interactors/brand_spec/build_test.rb
git commit -m "feat(brand_spec): Build interactor assembles the canonical brand-spec"
```

---

## Task 3: Onboarding Branding step (collect colors + app-icon)

**Files:**
- Modify: `app/controllers/operator/onboarding_controller.rb` (`branding_params`, `new` action's `@branding_incomplete`)
- Modify: `app/views/operator/onboarding/new_branding.html.erb`
- Test: `test/controllers/operator/onboarding_branding_test.rb`

- [ ] **Step 1: Write the failing integration test**

Create `test/controllers/operator/onboarding_branding_test.rb`:
```ruby
require "test_helper"

class Operator::OnboardingBrandingTest < ActionDispatch::IntegrationTest
  setup do
    setup_initial_user_fixtures
    @operator = operators(:cowork_tahoe)
    @admin    = users(:cowork_tahoe_admin)
  end

  test "branding step saves brand colors and app icon" do
    log_in @admin
    patch create_branding_operator_onboarding_index_path,
      params: {
        operator: {
          primary_color: "#123456",
          accent_color: "#654321",
          app_icon_image: fixture_file_upload("files/app_icon.png", "image/png")
        }
      },
      env: default_env

    @operator.reload
    assert_equal "#123456", @operator.primary_color
    assert_equal "#654321", @operator.accent_color
    assert @operator.app_icon_image.attached?
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `bin/rails test test/controllers/operator/onboarding_branding_test.rb`
Expected: FAIL — colors/app_icon are not permitted, so they aren't saved (assertions fail).

- [ ] **Step 3: Permit the new params**

In `app/controllers/operator/onboarding_controller.rb`, find `branding_params` (around line 276):
```ruby
  def branding_params
    params.require(:operator).permit(:logo_image, :snippet, :membership_text, :terms_of_service)
  end
```
Change it to:
```ruby
  def branding_params
    params.require(:operator).permit(:logo_image, :snippet, :membership_text, :terms_of_service,
                                     :primary_color, :accent_color, :app_icon_image)
  end
```

- [ ] **Step 4: Run to verify it passes**

Run: `bin/rails test test/controllers/operator/onboarding_branding_test.rb`
Expected: PASS.

- [ ] **Step 5: Add the form fields to the view**

In `app/views/operator/onboarding/new_branding.html.erb`, immediately AFTER the `:logo_image` `form-group` div (the one with `f.file_field :logo_image`) and BEFORE the `:snippet` group, insert:
```erb
    <div class="form-group">
      <%= f.label :app_icon_image, "App icon (square, ≥1024px, transparent PNG preferred)" %>
      <% if @operator.app_icon_image.attached? %>
        <div class="mb-2"><%= image_tag @operator.app_icon_image, width: 88 %></div>
      <% end %>
      <%= f.file_field :app_icon_image, accept: "image/*", class: "form-control-file" %>
    </div>

    <div class="form-group">
      <%= f.label :primary_color, "Primary brand color" %>
      <%= f.color_field :primary_color, value: (@operator.primary_color.presence || "#000000"), class: "form-control form-control-color" %>
    </div>

    <div class="form-group">
      <%= f.label :accent_color, "Accent color" %>
      <%= f.color_field :accent_color, value: (@operator.accent_color.presence || "#000000"), class: "form-control form-control-color" %>
    </div>
```

- [ ] **Step 6: Gate onboarding completeness on the new fields**

In the same controller's `new` action (around line 9), find:
```ruby
    @branding_incomplete = !current_tenant.logo_image.attached? ||
                           !current_tenant.terms_of_service.attached? ||
                           current_tenant.snippet.blank? ||
                           current_tenant.snippet == "Generic snippet about the space"
```
Append two conditions:
```ruby
    @branding_incomplete = !current_tenant.logo_image.attached? ||
                           !current_tenant.terms_of_service.attached? ||
                           current_tenant.snippet.blank? ||
                           current_tenant.snippet == "Generic snippet about the space" ||
                           current_tenant.primary_color.blank? ||
                           !current_tenant.app_icon_image.attached?
```

- [ ] **Step 7: Confirm the page renders (no template error)**

Run: `bin/rails test test/controllers/operator/onboarding_branding_test.rb`
Expected: still PASS. Then add a GET render check to the same test file inside the class and re-run:
```ruby
  test "branding page renders with the new fields" do
    log_in @admin
    get new_branding_operator_onboarding_index_path, env: default_env
    assert_response :success
    assert_select "input[name=?]", "operator[primary_color]"
    assert_select "input[name=?]", "operator[app_icon_image]"
  end
```
Run again: `bin/rails test test/controllers/operator/onboarding_branding_test.rb` → PASS (2 tests).

- [ ] **Step 8: Commit**

```bash
git add app/controllers/operator/onboarding_controller.rb app/views/operator/onboarding/new_branding.html.erb test/controllers/operator/onboarding_branding_test.rb
git commit -m "feat(onboarding): collect brand colors + app icon in the branding step"
```

---

## Task 4: brand_spec API endpoint

**Files:**
- Create: `app/controllers/api/v1/brand_specs_controller.rb`
- Modify: `config/routes.rb`
- Test: `test/controllers/api/v1/brand_specs_controller_test.rb`

- [ ] **Step 1: Write the failing request test**

Create `test/controllers/api/v1/brand_specs_controller_test.rb`:
```ruby
require "test_helper"

class Api::V1::BrandSpecsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @operator = operators(:cowork_tahoe)
    @operator.update!(primary_color: "#76B82A", accent_color: "#E8871E")
    ENV["BRAND_SPEC_TOKEN"] = "test-secret"
  end

  teardown { ENV.delete("BRAND_SPEC_TOKEN") }

  test "returns the brand-spec with a valid service token" do
    get "/api/v1/brand_spec", headers: {
      "Authorization" => "Bearer test-secret",
      "X-Operator-Subdomain" => @operator.subdomain
    }
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal @operator.subdomain, body["subdomain"]
    assert_equal "#76B82A", body.dig("colors", "primary")
    assert_equal "https://#{@operator.subdomain}.jellyswitch.com/api/v1", body["apiBase"]
  end

  test "401 without the service token" do
    get "/api/v1/brand_spec", headers: { "X-Operator-Subdomain" => @operator.subdomain }
    assert_response :unauthorized
  end

  test "404 for an unknown subdomain" do
    get "/api/v1/brand_spec", headers: {
      "Authorization" => "Bearer test-secret",
      "X-Operator-Subdomain" => "nope-not-real"
    }
    assert_response :not_found
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `bin/rails test test/controllers/api/v1/brand_specs_controller_test.rb`
Expected: FAIL — routing error (no `/api/v1/brand_spec` route).

- [ ] **Step 3: Add the route**

In `config/routes.rb`, inside `namespace :api do … namespace :v1 do … end end` (near the other `get '…'` lines, e.g. after line 31 `get 'auth/operators', …`), add:
```ruby
      get 'brand_spec', to: 'brand_specs#show'
```

- [ ] **Step 4: Implement the controller**

Create `app/controllers/api/v1/brand_specs_controller.rb`:
```ruby
# Serves the canonical brand-spec for the mobile scaffolder / CI. Auth is a
# shared service token (no JWT user), and the operator is resolved by the
# X-Operator-Subdomain header. Inherits Api::V1::BaseController for url_for +
# CSRF skipping, but skips the user-auth/tenant before_actions.
class Api::V1::BrandSpecsController < Api::V1::BaseController
  skip_before_action :authenticate_api_v1, :set_tenant_from_header, :enforce_tenant_scope!, raise: false
  before_action :authenticate_service_token!
  before_action :set_operator

  def show
    result = BrandSpec::Build.call(
      operator: @operator,
      app_icon_url: (@operator.app_icon_image.attached? ? url_for(@operator.app_icon_image) : nil),
      wordmark_url: (@operator.logo_image.attached? ? url_for(@operator.logo_image) : nil)
    )
    render json: result.brand_spec
  end

  private

  def authenticate_service_token!
    expected = ENV["BRAND_SPEC_TOKEN"].to_s
    token = request.headers["Authorization"].to_s.split(" ").last.to_s
    return head(:unauthorized) if expected.blank?
    head :unauthorized unless ActiveSupport::SecurityUtils.secure_compare(token, expected)
  end

  def set_operator
    @operator = Operator.find_by(subdomain: request.headers["X-Operator-Subdomain"].to_s.downcase)
    head :not_found unless @operator
  end
end
```

- [ ] **Step 5: Run to verify it passes**

Run: `bin/rails test test/controllers/api/v1/brand_specs_controller_test.rb`
Expected: PASS (3 tests).

- [ ] **Step 6: Commit**

```bash
git add app/controllers/api/v1/brand_specs_controller.rb config/routes.rb test/controllers/api/v1/brand_specs_controller_test.rb
git commit -m "feat(api): GET /api/v1/brand_spec (service-token, subdomain-scoped)"
```

---

## Task 5: Full verification

- [ ] **Step 1: Run all the new/affected tests together**

Run:
```bash
bin/rails test \
  test/models/operator_test.rb \
  test/interactors/brand_spec/build_test.rb \
  test/controllers/operator/onboarding_branding_test.rb \
  test/controllers/api/v1/brand_specs_controller_test.rb
```
Expected: all green, 0 failures, 0 errors.

- [ ] **Step 2: Sanity-check the contract shape matches the mobile engine**

The mobile engine (`scripts/lib/load-brand-spec.mjs`, separate repo) consumes `{ name, subdomain, colors.primary, assets.appIcon }` as required and derives the rest. Confirm the JSON keys in `BrandSpec::Build` are exactly: `key, name, subdomain, apiBase, bundleId.{ios,android}, colors.{primary,accent}, splashBackground, assets.{appIcon,wordmark}`. (They are — this step is a read-only check.)

- [ ] **Step 3: Commit any fixups** made during verification (if none, skip).

---

## Notes for the implementer

- `setup_initial_user_fixtures`, `log_in`, and `default_env` are existing test helpers (see `test/controllers/operator/beacons_controller_test.rb` for the pattern). Fixtures `operators(:cowork_tahoe)`, `users(:cowork_tahoe_admin)` already exist.
- `BRAND_SPEC_TOKEN` is read from ENV here for testability; in production set it via the platform env / Rails credentials and give the CI the same value (piece 3).
- This piece does NOT trigger the scaffolder — that's piece 3 (`…-brand-scaffold-automation-design.md`). It only collects + exposes the data.
- Out of scope (spec): auto-suggesting colors from the uploaded logo.
