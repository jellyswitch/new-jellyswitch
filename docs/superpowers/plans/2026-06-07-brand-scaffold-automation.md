# Brand Scaffold Automation (Trigger) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A "Create mobile app" button on operator onboarding fires a Sidekiq job that triggers a mobile-repo GitHub Action, which runs the `new-brand` engine and opens a PR.

**Architecture:** Backend: a controller action (guarded + idempotent) enqueues `MobileApp::RequestScaffoldJob`, which POSTs a `workflow_dispatch` to the mobile repo via HTTParty using a credentials token. Mobile repo: a `new-brand.yml` GitHub Action runs the engine `--subdomain <sub> --ci` and opens a PR. Build/submit stay developer-driven.

**Tech Stack:** Rails 7.2 (Sidekiq/ActiveJob, HTTParty, WebMock+mocha tests) in `new-jellyswitch`; GitHub Actions YAML + the existing `npm run new-brand` engine in `jellyswitch-mobile`.

**Spec:** `~/Downloads/jellyswitch-mobile/docs/superpowers/specs/2026-06-07-brand-scaffold-automation-design.md` (piece 3 of 3).

## Two repos / two environments

- **Backend tasks (1, 2)** run in `~/Downloads/new-jellyswitch`. Every ruby/rails command MUST be prefixed (shell doesn't persist between calls):
  ```
  export PATH="$HOME/.rbenv/versions/3.3.10/bin:$PATH"
  ```
  `bin/rails -v` → `Rails 7.2.3.1`. Test: `bin/rails test <file>`.
- **Mobile task (3)** runs in `~/Downloads/jellyswitch-mobile` (Node; `npm run test:scripts` for the engine).
- **Task 4** is docs/secrets (either repo as noted).

## File structure

| File | Repo | Responsibility |
|------|------|----------------|
| `db/migrate/<ts>_add_mobile_app_requested_at_to_operators.rb` | backend | idempotency timestamp |
| `app/jobs/mobile_app/request_scaffold_job.rb` | backend | POST workflow_dispatch to the mobile repo |
| `app/controllers/operator/onboarding_controller.rb` | backend | `request_mobile_app` action + `branding_complete?` helper |
| `app/views/operator/onboarding/new.html.erb` | backend | "Create mobile app" button |
| `config/routes.rb` | backend | `post :request_mobile_app` |
| `.github/workflows/new-brand.yml` | mobile | the Action that runs the engine + opens a PR |
| `docs/AUTOMATION_SETUP.md` | mobile | secrets + how to wire it up |
| test files | backend | job + controller tests |

---

## Task 1: Migration + RequestScaffoldJob (backend)

**Files:**
- Create: `db/migrate/<ts>_add_mobile_app_requested_at_to_operators.rb`
- Create: `app/jobs/mobile_app/request_scaffold_job.rb`
- Test: `test/jobs/mobile_app/request_scaffold_job_test.rb`

- [ ] **Step 1: Generate + run the migration**

```
export PATH="$HOME/.rbenv/versions/3.3.10/bin:$PATH"
bin/rails g migration AddMobileAppRequestedAtToOperators mobile_app_requested_at:datetime
bin/rails db:migrate
```
Expected: `operators.mobile_app_requested_at` datetime column in `db/schema.rb`.

- [ ] **Step 2: Write the failing job test**

Create `test/jobs/mobile_app/request_scaffold_job_test.rb`:
```ruby
require "test_helper"

class MobileApp::RequestScaffoldJobTest < ActiveJob::TestCase
  setup do
    @operator = operators(:cowork_tahoe)
    ENV["GITHUB_SCAFFOLD_TOKEN"] = "ghtok"
    @url = "https://api.github.com/repos/jellyswitch/jellyswitch-mobile/actions/workflows/new-brand.yml/dispatches"
  end

  teardown { ENV.delete("GITHUB_SCAFFOLD_TOKEN") }

  test "dispatches the workflow with the operator subdomain" do
    stub = stub_request(:post, @url)
      .with(
        headers: { "Authorization" => "Bearer ghtok" },
        body: { ref: "main", inputs: { subdomain: @operator.subdomain } }.to_json
      )
      .to_return(status: 204)

    MobileApp::RequestScaffoldJob.perform_now(@operator.id)
    assert_requested stub
  end

  test "raises on a non-2xx response so Sidekiq retries" do
    stub_request(:post, @url).to_return(status: 422, body: "nope")
    assert_raises(MobileApp::RequestScaffoldJob::DispatchError) do
      MobileApp::RequestScaffoldJob.perform_now(@operator.id)
    end
  end
end
```

- [ ] **Step 3: Run — verify FAIL**

```
export PATH="$HOME/.rbenv/versions/3.3.10/bin:$PATH"
bin/rails test test/jobs/mobile_app/request_scaffold_job_test.rb
```
Expected: FAIL — `uninitialized constant MobileApp::RequestScaffoldJob`.

- [ ] **Step 4: Implement the job**

Create `app/jobs/mobile_app/request_scaffold_job.rb`:
```ruby
module MobileApp
  # Triggers the mobile repo's new-brand GitHub Action for an operator's
  # subdomain. The Action runs the scaffolder and opens a PR (build/submit stay
  # developer-driven). Token comes from ENV or Rails credentials.
  class RequestScaffoldJob < ApplicationJob
    queue_as :default

    class DispatchError < StandardError; end

    REPO = "jellyswitch/jellyswitch-mobile".freeze
    WORKFLOW = "new-brand.yml".freeze

    def perform(operator_id)
      operator = ActsAsTenant.without_tenant { Operator.find_by(id: operator_id) }
      return unless operator

      response = HTTParty.post(
        "https://api.github.com/repos/#{REPO}/actions/workflows/#{WORKFLOW}/dispatches",
        headers: {
          "Authorization" => "Bearer #{github_token}",
          "Accept" => "application/vnd.github+json",
          "X-GitHub-Api-Version" => "2022-11-28",
          "User-Agent" => "jellyswitch-backend"
        },
        body: { ref: "main", inputs: { subdomain: operator.subdomain } }.to_json,
        timeout: 15
      )

      return if response.code.between?(200, 299)

      raise DispatchError, "workflow_dispatch failed (#{response.code}): #{response.body}"
    end

    private

    def github_token
      ENV["GITHUB_SCAFFOLD_TOKEN"].presence ||
        Rails.application.credentials.dig(:github, :scaffold_token)
    end
  end
end
```

- [ ] **Step 5: Run — verify PASS**

```
export PATH="$HOME/.rbenv/versions/3.3.10/bin:$PATH"
bin/rails test test/jobs/mobile_app/request_scaffold_job_test.rb
```
Expected: PASS (2 tests).

- [ ] **Step 6: Commit**

```
git add db/migrate db/schema.rb app/jobs/mobile_app/request_scaffold_job.rb test/jobs/mobile_app/request_scaffold_job_test.rb
git commit -m "feat(mobile_app): RequestScaffoldJob dispatches the mobile-repo workflow"
```

---

## Task 2: Controller action + route + button (backend)

**Files:**
- Modify: `app/controllers/operator/onboarding_controller.rb`
- Modify: `config/routes.rb`
- Modify: `app/views/operator/onboarding/new.html.erb`
- Test: `test/controllers/operator/onboarding_request_mobile_app_test.rb`

- [ ] **Step 1: Write the failing integration test**

Create `test/controllers/operator/onboarding_request_mobile_app_test.rb`:
```ruby
require "test_helper"

class Operator::OnboardingRequestMobileAppTest < ActionDispatch::IntegrationTest
  setup do
    setup_initial_user_fixtures
    @operator = operators(:cowork_tahoe)
    @admin    = users(:cowork_tahoe_admin)
    # make branding "complete"
    @operator.update!(snippet: "A real space", primary_color: "#76B82A", accent_color: "#E8871E")
    @operator.logo_image.attach(io: File.open(Rails.root.join("test/fixtures/files/app_icon.png")), filename: "l.png", content_type: "image/png")
    @operator.terms_of_service.attach(io: File.open(Rails.root.join("test/fixtures/files/app_icon.png")), filename: "t.pdf", content_type: "application/pdf")
    @operator.app_icon_image.attach(io: File.open(Rails.root.join("test/fixtures/files/app_icon.png")), filename: "i.png", content_type: "image/png")
  end

  test "enqueues the scaffold job and stamps the operator" do
    log_in @admin
    assert_enqueued_with(job: MobileApp::RequestScaffoldJob) do
      post request_mobile_app_operator_onboarding_index_path, env: default_env
    end
    assert @operator.reload.mobile_app_requested_at.present?
  end

  test "does not enqueue twice (idempotent)" do
    @operator.update!(mobile_app_requested_at: Time.current)
    log_in @admin
    assert_no_enqueued_jobs only: MobileApp::RequestScaffoldJob do
      post request_mobile_app_operator_onboarding_index_path, env: default_env
    end
  end
end
```

- [ ] **Step 2: Run — verify FAIL**

```
export PATH="$HOME/.rbenv/versions/3.3.10/bin:$PATH"
bin/rails test test/controllers/operator/onboarding_request_mobile_app_test.rb
```
Expected: FAIL — no route `request_mobile_app_operator_onboarding_index_path`.

- [ ] **Step 3: Add the route**

In `config/routes.rb`, inside the `resources :onboarding, controller: "operator/onboarding", as: :operator_onboarding do collection do … end end` block (next to the other collection routes like `get :skip`), add:
```ruby
      post :request_mobile_app
```

- [ ] **Step 4: Add a `branding_complete?` helper + the action**

In `app/controllers/operator/onboarding_controller.rb`, add these private methods (near the other private methods, after `branding_params`):
```ruby
  def branding_complete?(operator)
    operator.logo_image.attached? &&
      operator.terms_of_service.attached? &&
      operator.app_icon_image.attached? &&
      operator.snippet.present? &&
      operator.snippet != "Generic snippet about the space" &&
      operator.primary_color.present?
  end
```
Then add the public action (near the other actions, e.g. after `def create_branding`):
```ruby
  def request_mobile_app
    if current_tenant.mobile_app_requested_at.present?
      flash[:notice] = "Mobile app already requested."
    elsif !branding_complete?(current_tenant)
      flash[:error] = "Complete branding (logo, app icon, colors, description, terms) first."
    else
      current_tenant.update!(mobile_app_requested_at: Time.current)
      MobileApp::RequestScaffoldJob.perform_later(current_tenant.id)
      flash[:success] = "Mobile app build requested — a developer will review the PR."
    end
    turbo_redirect(new_operator_onboarding_path, action: "replace")
  end
```
(`turbo_redirect` is used throughout this controller; reuse it.)

- [ ] **Step 5: Refactor `new` to reuse the helper (DRY)**

In the `new` action, replace the inline `@branding_incomplete = …` assignment with:
```ruby
    @branding_incomplete = !branding_complete?(current_tenant)
```

- [ ] **Step 6: Run — verify PASS**

```
export PATH="$HOME/.rbenv/versions/3.3.10/bin:$PATH"
bin/rails test test/controllers/operator/onboarding_request_mobile_app_test.rb test/controllers/operator/onboarding_branding_test.rb
```
Expected: PASS (the new 2 tests + the existing branding tests still pass — the refactor must not break them).

- [ ] **Step 7: Add the button to the hub view**

In `app/views/operator/onboarding/new.html.erb`, add near the end of the card/content (after the existing onboarding-step list; pick a sensible spot at the bottom of the main content block):
```erb
<% if !@branding_incomplete %>
  <div class="mt-4">
    <% if current_tenant.mobile_app_requested_at.present? %>
      <p class="text-muted">Mobile app requested on <%= current_tenant.mobile_app_requested_at.to_date %>.</p>
    <% else %>
      <%= button_to "Create mobile app", request_mobile_app_operator_onboarding_index_path,
            method: :post, class: "btn btn-outline-primary" %>
    <% end %>
  </div>
<% end %>
```

- [ ] **Step 8: Re-run to confirm the view renders**

```
export PATH="$HOME/.rbenv/versions/3.3.10/bin:$PATH"
bin/rails test test/controllers/operator/onboarding_request_mobile_app_test.rb
```
Expected: still PASS.

- [ ] **Step 9: Commit**

```
git add app/controllers/operator/onboarding_controller.rb config/routes.rb app/views/operator/onboarding/new.html.erb test/controllers/operator/onboarding_request_mobile_app_test.rb
git commit -m "feat(onboarding): Create mobile app button enqueues the scaffold job"
```

---

## Task 3: GitHub Action (mobile repo)

**Repo:** `~/Downloads/jellyswitch-mobile` (Node). Work on a branch there: `git checkout -b claude/new-brand-workflow`.

**Files:**
- Create: `.github/workflows/new-brand.yml`

- [ ] **Step 1: Create the workflow**

Create `.github/workflows/new-brand.yml`:
```yaml
name: new-brand

on:
  workflow_dispatch:
    inputs:
      subdomain:
        description: "Operator subdomain to scaffold"
        required: true
        type: string

permissions:
  contents: write
  pull-requests: write

jobs:
  scaffold:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - uses: actions/setup-node@v4
        with:
          node-version: 20
      - run: npm ci
      - name: Scaffold the brand
        env:
          BRAND_SPEC_TOKEN: ${{ secrets.BRAND_SPEC_TOKEN }}
        run: npm run new-brand -- --subdomain "${{ inputs.subdomain }}" --ci
      - name: Open a PR
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          BRANCH="brand/${{ inputs.subdomain }}"
          git config user.name "jellyswitch-bot"
          git config user.email "bot@jellyswitch.com"
          git checkout -b "$BRANCH"
          git add -A
          git commit -m "Scaffold ${{ inputs.subdomain }} brand (automated)"
          git push -u origin "$BRANCH"
          gh pr create --base main --head "$BRANCH" \
            --title "Scaffold brand: ${{ inputs.subdomain }}" \
            --body "Automated brand scaffold for \`${{ inputs.subdomain }}\`. Review: confirm bundle IDs, run \`eas project:create\`, add Firebase google-services.json, then build + submit. (Operational config lives in the backend onboarding.)"
```

- [ ] **Step 2: Validate the YAML parses**

Run: `cd ~/Downloads/jellyswitch-mobile && python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/new-brand.yml')); print('YAML OK')"`
Expected: `YAML OK`. (If `actionlint` is installed, also run `actionlint .github/workflows/new-brand.yml` and expect no errors.)

- [ ] **Step 3: Confirm the engine accepts the invocation (offline smoke)**

The real run needs the backend `/brand_spec` (Task 4 secrets). Offline, confirm the CLI parses the flags without a backend by checking the help/guard path:
Run: `cd ~/Downloads/jellyswitch-mobile && node scripts/new-brand.mjs --ci 2>&1 | head -3`
Expected: it errors with `--ci requires --from-spec or --subdomain` (proves `--ci` is wired; the workflow always passes `--subdomain`).

- [ ] **Step 4: Commit (mobile repo)**

```bash
cd ~/Downloads/jellyswitch-mobile
git add .github/workflows/new-brand.yml
git commit -m "ci: new-brand workflow (scaffold brand on dispatch, open PR)"
```

---

## Task 4: Secrets + setup docs (mobile repo)

**Files:**
- Create: `~/Downloads/jellyswitch-mobile/docs/AUTOMATION_SETUP.md`

- [ ] **Step 1: Write the setup doc**

Create `docs/AUTOMATION_SETUP.md`:
```markdown
# Brand scaffold automation — setup

End-to-end: operator clicks **Create mobile app** in onboarding → backend
`MobileApp::RequestScaffoldJob` → GitHub `workflow_dispatch` → `new-brand.yml`
runs the engine `--subdomain <sub> --ci` → opens a PR. A developer reviews the
PR, then builds + submits (native build + store review stay manual).

## Secrets to set (once)

**Backend (`new-jellyswitch`)** — a GitHub token that can dispatch workflows on
`jellyswitch/jellyswitch-mobile`:
- Fine-grained PAT (or GitHub App) with **Actions: read/write** on the mobile repo.
- Provide to the backend as env `GITHUB_SCAFFOLD_TOKEN` (or
  `Rails.application.credentials.github.scaffold_token`).
- Also set `BRAND_SPEC_TOKEN` (any strong secret) so `/api/v1/brand_spec` is
  authenticated.

**Mobile repo (`jellyswitch-mobile`) → Settings → Secrets → Actions:**
- `BRAND_SPEC_TOKEN` — the SAME value as the backend's, so the Action can read
  `/api/v1/brand_spec`.
- `GITHUB_TOKEN` is provided automatically to the Action (used by `gh`/push).

## Test it
1. Ensure the operator exists and finished onboarding (branding complete).
2. Click **Create mobile app**, or manually: `gh workflow run new-brand.yml -f subdomain=<sub>` in the mobile repo.
3. A `brand/<sub>` PR should appear within a few minutes.

## Boundary
The automation stops at the PR (+ optional Android build, not enabled by
default). Build + store submission stay developer-driven.
```

- [ ] **Step 2: Commit (mobile repo)**

```bash
cd ~/Downloads/jellyswitch-mobile
git add docs/AUTOMATION_SETUP.md
git commit -m "docs: brand scaffold automation setup (secrets + flow)"
```

---

## Task 5: Verification

- [ ] **Step 1: Backend — run all piece-3 + adjacent tests**

```
cd ~/Downloads/new-jellyswitch && export PATH="$HOME/.rbenv/versions/3.3.10/bin:$PATH"
bin/rails test \
  test/jobs/mobile_app/request_scaffold_job_test.rb \
  test/controllers/operator/onboarding_request_mobile_app_test.rb \
  test/controllers/operator/onboarding_branding_test.rb
```
Expected: all green, 0 failures.

- [ ] **Step 2: Mobile — engine suite still green + workflow parses**

```bash
cd ~/Downloads/jellyswitch-mobile
npm run test:scripts 2>&1 | grep -E "ℹ (tests|pass|fail)"
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/new-brand.yml')); print('YAML OK')"
```
Expected: engine suite passes; `YAML OK`.

- [ ] **Step 3: Note the manual gate**

The button → job → dispatch → PR chain cannot be fully exercised without the real secrets (Task 4). After secrets are set, the acceptance test is: click **Create mobile app** (or `gh workflow run new-brand.yml -f subdomain=<sub>`) and confirm a `brand/<sub>` PR appears. Record this as the remaining manual verification.

---

## Notes for the implementer

- Backend tasks need the `PATH` export (Ruby 3.3.10) on every command; mobile tasks are Node.
- Two separate git repos / commits: backend (Tasks 1, 2) on a backend feature branch; mobile (Tasks 3, 4) on a mobile feature branch.
- The job raises `DispatchError` on non-2xx so Sidekiq retries; idempotency is the operator's `mobile_app_requested_at` (set by the controller before enqueue).
- YAGNI: no auto-`eas project:create`, no Android auto-build (it's a documented optional input only if you add it later), no auto store submission.
