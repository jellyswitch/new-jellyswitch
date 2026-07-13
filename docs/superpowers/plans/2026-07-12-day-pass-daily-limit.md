# Day Pass Daily Limit by Type — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let an operator cap how many day passes of a given type can exist per day (e.g. Cowork Tahoe "Day Office": 2/day), blocking member self-serve paths at the cap while staff and door-entry paths pass through.

**Architecture:** One nullable `daily_limit` column on `day_pass_types` + one gate method `DayPassType#daily_limit_reached?(day:, location:)` that counts EVERY `DayPass` row of that type/day/location. The gate is called from exactly three member self-serve entry points (API single-pass create, API reschedule, bundle day-scheduling via an opt-in interactor flag) plus the web member buy flow. No other path calls it — staff/admin, door burns, and reservation-coverage passes are intentionally ungated (their rows still count).

**Tech Stack:** Rails (repo `~/Downloads/new-jellyswitch`), Minitest (`ActionDispatch::IntegrationTest` + `ActiveSupport::TestCase`), fixtures + FactoryBot, acts_as_tenant.

**Spec:** `docs/superpowers/specs/2026-07-12-day-pass-daily-limit-design.md` (approved 2026-07-12).

**Environment notes:**
- Work in a **worktree off `origin/main`** — the shared checkout is on an unrelated branch and dirty. Merging to main auto-deploys production; do NOT merge without David's go.
- Run tests with `PARALLEL_WORKERS=1` (pg segfault workaround, see memory).
- Ruby via rbenv (3.3.10).

---

### Task 0: Worktree + branch + commit the spec

**Files:**
- Create: worktree at `~/Downloads/new-jellyswitch-worktrees/day-pass-daily-limit`
- Commit: `docs/superpowers/specs/2026-07-12-day-pass-daily-limit-design.md`, `docs/superpowers/plans/2026-07-12-day-pass-daily-limit.md`

- [ ] **Step 0.1: Create the worktree**

```bash
cd ~/Downloads/new-jellyswitch
git fetch origin
git worktree add ~/Downloads/new-jellyswitch-worktrees/day-pass-daily-limit -b feat/day-pass-daily-limit origin/main
```

- [ ] **Step 0.2: Copy the spec + plan into the worktree and commit**

The spec and plan were written in the main checkout (uncommitted). Copy them in:

```bash
cd ~/Downloads/new-jellyswitch-worktrees/day-pass-daily-limit
mkdir -p docs/superpowers/specs docs/superpowers/plans
cp ~/Downloads/new-jellyswitch/docs/superpowers/specs/2026-07-12-day-pass-daily-limit-design.md docs/superpowers/specs/
cp ~/Downloads/new-jellyswitch/docs/superpowers/plans/2026-07-12-day-pass-daily-limit.md docs/superpowers/plans/
git add docs/superpowers
git commit -m "docs: day-pass daily limit spec + plan"
```

- [ ] **Step 0.3: Verify the suite boots**

Run: `cd ~/Downloads/new-jellyswitch-worktrees/day-pass-daily-limit && bundle install --quiet && PARALLEL_WORKERS=1 bin/rails test test/models/day_pass_type_test.rb`
Expected: existing tests PASS (2 tests, 0 failures).

---

### Task 1: `daily_limit` column + validation + gate method

**Files:**
- Create: `db/migrate/20260712200000_add_daily_limit_to_day_pass_types.rb`
- Modify: `app/models/day_pass_type.rb`
- Test: `test/models/day_pass_type_test.rb`

- [ ] **Step 1.1: Write the failing tests**

Append inside `class DayPassTypeTest` in `test/models/day_pass_type_test.rb`:

```ruby
  # --- daily_limit (per-day sales cap) ---

  test "daily_limit must be a positive integer when present" do
    dpt = day_pass_type(:cowork_tahoe_day_pass_type)
    dpt.daily_limit = 0
    assert_not dpt.valid?
    dpt.daily_limit = 2
    assert dpt.valid?
    dpt.daily_limit = nil
    assert dpt.valid?, "nil daily_limit means unlimited and must be valid"
  end

  test "daily_limit_reached? is always false when no limit is set" do
    dpt = day_pass_type(:cowork_tahoe_day_pass_type)
    assert_nil dpt.daily_limit
    assert_not dpt.daily_limit_reached?(day: Date.current, location: @location)
  end

  test "daily_limit_reached? counts every pass of the type on that day at that location" do
    operator = operators(:cowork_tahoe)
    dpt = day_pass_type(:cowork_tahoe_day_pass_type)
    dpt.update!(daily_limit: 2)
    day = Date.current + 3

    ActsAsTenant.with_tenant(operator) do
      # 1st pass: a normal purchased pass
      DayPass.create!(user: @user, billable: @user, operator: operator,
                      location: @location, day_pass_type: dpt, day: day, imported: true)
      assert_not dpt.daily_limit_reached?(day: day, location: @location),
                 "1 of 2 is under the limit"

      # 2nd pass: complimentary — still counts (limit models physical capacity)
      other = users(:cowork_tahoe_non_member)
      DayPass.create!(user: other, billable: other, operator: operator,
                      location: @location, day_pass_type: dpt, day: day,
                      complimentary: true, imported: true)
      assert dpt.daily_limit_reached?(day: day, location: @location),
             "2 of 2 reaches the limit; complimentary passes count"

      # Different day and different location are unaffected
      assert_not dpt.daily_limit_reached?(day: day + 1, location: @location)
      other_location = Location.where.not(id: @location.id).first
      assert_not dpt.daily_limit_reached?(day: day, location: other_location)
    end
  end
```

- [ ] **Step 1.2: Run tests to verify they fail**

Run: `PARALLEL_WORKERS=1 bin/rails test test/models/day_pass_type_test.rb`
Expected: FAIL / ERROR — `undefined method 'daily_limit'` (column doesn't exist yet).

- [ ] **Step 1.3: Write the migration**

Create `db/migrate/20260712200000_add_daily_limit_to_day_pass_types.rb`:

```ruby
class AddDailyLimitToDayPassTypes < ActiveRecord::Migration[7.2]
  def change
    # Max DayPass rows of this type per calendar day (per location — the type
    # is already location-scoped). NULL = unlimited, the default for every
    # existing type. See docs/superpowers/specs/2026-07-12-day-pass-daily-limit-design.md.
    add_column :day_pass_types, :daily_limit, :integer
  end
end
```

Run: `bin/rails db:migrate && RAILS_ENV=test bin/rails db:migrate`
Expected: migration runs cleanly; `db/schema.rb` gains `t.integer "daily_limit"` under `day_pass_types`.

- [ ] **Step 1.4: Add validation + gate method to the model**

In `app/models/day_pass_type.rb`, directly below the existing
`validates :quantity, ...` line, add:

```ruby
  validates :daily_limit, numericality: { only_integer: true, greater_than_or_equal_to: 1 },
                          allow_nil: true
```

And below the `bundle?` method, add:

```ruby
  # Daily sales cap. Every DayPass row of this type on that day at that
  # location counts — purchased, comped, or bundle-sourced — because the limit
  # models physical capacity (e.g. the building has 2 day offices), not sales
  # volume. Enforced only at member self-serve entry points; staff/admin and
  # door-entry paths never call this (their rows still count).
  def daily_limit_reached?(day:, location:)
    return false if daily_limit.nil?
    day_passes.where(location: location, day: day).count >= daily_limit
  end
```

- [ ] **Step 1.5: Run tests to verify they pass**

Run: `PARALLEL_WORKERS=1 bin/rails test test/models/day_pass_type_test.rb`
Expected: PASS (5 tests, 0 failures).

- [ ] **Step 1.6: Commit**

```bash
git add db/migrate/20260712200000_add_daily_limit_to_day_pass_types.rb db/schema.rb \
        app/models/day_pass_type.rb test/models/day_pass_type_test.rb
git commit -m "feat(day-passes): daily_limit column + gate on DayPassType"
```

---

### Task 2: Gate the API single-pass purchase

**Files:**
- Modify: `app/controllers/api/v1/day_passes_controller.rb` (in `#create`, right after the `date = ...` line, ~line 100)
- Test: Create `test/controllers/api/v1/day_passes_daily_limit_test.rb`

- [ ] **Step 2.1: Write the failing tests**

Create `test/controllers/api/v1/day_passes_daily_limit_test.rb`:

```ruby
require "test_helper"

# Member self-serve purchase respects DayPassType#daily_limit.
# Spec: docs/superpowers/specs/2026-07-12-day-pass-daily-limit-design.md
class Api::V1::DayPassesDailyLimitTest < ActionDispatch::IntegrationTest
  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @member   = users(:cowork_tahoe_member)
    @type     = day_pass_type(:cowork_tahoe_day_pass_type)
    @day      = (Date.current + 2)
  end

  def headers(user = @member)
    token = JWT.encode(
      { user_id: user.id, operator_id: @operator.id, exp: 30.days.from_now.to_i },
      Rails.application.secret_key_base,
      "HS256",
    )
    { "Authorization" => "Bearer #{token}", "X-Operator-Subdomain" => @operator.subdomain }
  end

  def fill_day(count)
    ActsAsTenant.with_tenant(@operator) do
      count.times do
        u = create(:user, operator: @operator, original_location: @location, current_location: @location)
        DayPass.create!(user: u, billable: u, operator: @operator, location: @location,
                        day_pass_type: @type, day: @day, imported: true)
      end
    end
  end

  test "purchase is blocked when the day is at the type's limit" do
    @type.update!(daily_limit: 2)
    fill_day(2)

    assert_no_difference -> { DayPass.count } do
      post "/api/v1/day_passes",
           params: { day_pass_type_id: @type.id, date: @day.iso8601 }, headers: headers
    end

    assert_response :unprocessable_entity
    assert_includes JSON.parse(response.body)["error"], "fully booked"
  end

  test "purchase proceeds past the gate when under the limit" do
    @type.update!(daily_limit: 2)
    fill_day(1)

    post "/api/v1/day_passes",
         params: { day_pass_type_id: @type.id, date: @day.iso8601 }, headers: headers

    # The fixture member has no Stripe billing, so the purchase fails LATER in
    # the interactor chain — the point here is only that the daily-limit gate
    # did not fire. A "fully booked" error would mean the gate is miscounting.
    refute_includes response.body, "fully booked"
  end

  test "no limit set means never blocked" do
    assert_nil @type.daily_limit
    fill_day(3)

    post "/api/v1/day_passes",
         params: { day_pass_type_id: @type.id, date: @day.iso8601 }, headers: headers

    refute_includes response.body, "fully booked"
  end
end
```

- [ ] **Step 2.2: Run tests to verify the blocked case fails**

Run: `PARALLEL_WORKERS=1 bin/rails test test/controllers/api/v1/day_passes_daily_limit_test.rb`
Expected: "purchase is blocked..." FAILS (no gate yet — response won't contain "fully booked"). The other two may already pass; that's fine.

- [ ] **Step 2.3: Add the gate to the controller**

In `app/controllers/api/v1/day_passes_controller.rb` `#create`, find:

```ruby
    # Single day pass — existing path unchanged
    date = params[:date].present? ? Date.parse(params[:date]) : Date.current
```

Immediately after it, add:

```ruby
    # Daily cap (physical capacity — e.g. 2 day offices). Member self-serve
    # only: staff/admin paths and door burns are intentionally ungated, though
    # their rows still count toward the tally. See
    # docs/superpowers/specs/2026-07-12-day-pass-daily-limit-design.md.
    if day_pass_type.daily_limit_reached?(day: date, location: current_location)
      return render_error("#{day_pass_type.name.pluralize} are fully booked for #{date.strftime('%B %e')}. Try another day.")
    end
```

- [ ] **Step 2.4: Run tests to verify they pass**

Run: `PARALLEL_WORKERS=1 bin/rails test test/controllers/api/v1/day_passes_daily_limit_test.rb`
Expected: PASS (3 tests, 0 failures).

- [ ] **Step 2.5: Commit**

```bash
git add app/controllers/api/v1/day_passes_controller.rb test/controllers/api/v1/day_passes_daily_limit_test.rb
git commit -m "feat(day-passes): block API purchase when the type's daily limit is reached"
```

---

### Task 3: Gate the API reschedule (target day)

**Files:**
- Modify: `app/controllers/api/v1/day_passes_controller.rb` (in `#reschedule`, after the past-date guard)
- Test: `test/controllers/api/v1/day_passes_reschedule_test.rb` (append)

- [ ] **Step 3.1: Write the failing tests**

Append inside the class in `test/controllers/api/v1/day_passes_reschedule_test.rb`
(reuse its existing `setup` — `@pass` is `day_passes(:cowork_tahoe_day_pass)`, type
`cowork_tahoe_day_pass_type`, day = 2 days from now):

```ruby
  test "cannot move a pass to a day at the type's daily limit" do
    @pass.day_pass_type.update!(daily_limit: 1)
    target = 5.days.from_now.to_date
    other = users(:cowork_tahoe_non_member)
    ActsAsTenant.with_tenant(@operator) do
      DayPass.create!(user: other, billable: other, operator: @operator, location: @location,
                      day_pass_type: @pass.day_pass_type, day: target, imported: true)
    end
    original = @pass.day

    patch "/api/v1/day_passes/#{@pass.id}/reschedule",
          params: { day: target.iso8601 }, headers: headers

    assert_response :unprocessable_entity
    assert_includes JSON.parse(response.body)["error"], "fully booked"
    assert_equal original, @pass.reload.day
  end

  test "a same-day 'move' is allowed even when the day is at the limit" do
    # The pass's own row fills the day — moving it onto its own day must not
    # count the pass against itself.
    @pass.day_pass_type.update!(daily_limit: 1)

    patch "/api/v1/day_passes/#{@pass.id}/reschedule",
          params: { day: @pass.day.iso8601 }, headers: headers

    assert_response :success
  end

  test "move succeeds when the target day has capacity under the limit" do
    @pass.day_pass_type.update!(daily_limit: 2)
    target = 5.days.from_now.to_date

    patch "/api/v1/day_passes/#{@pass.id}/reschedule",
          params: { day: target.iso8601 }, headers: headers

    assert_response :success
    assert_equal target, @pass.reload.day
  end
```

- [ ] **Step 3.2: Run tests to verify the blocked case fails**

Run: `PARALLEL_WORKERS=1 bin/rails test test/controllers/api/v1/day_passes_reschedule_test.rb`
Expected: "cannot move a pass to a day at the type's daily limit" FAILS (move succeeds, no gate yet). The two allowed-cases pass. All pre-existing tests still pass.

- [ ] **Step 3.3: Add the gate to `#reschedule`**

In `app/controllers/api/v1/day_passes_controller.rb` `#reschedule`, find:

```ruby
    return render_error("Passes can only be moved to today or a future date.") if new_day < today
```

Immediately after it, add:

```ruby
    # Daily cap on the TARGET day. Skipped when the pass isn't actually
    # changing days — its own row would otherwise count against itself.
    if new_day != day_pass.day &&
       day_pass.day_pass_type&.daily_limit_reached?(day: new_day, location: day_pass.location)
      return render_error("#{day_pass.day_pass_type.name.pluralize} are fully booked for #{new_day.strftime('%B %e')}. Try another day.")
    end
```

- [ ] **Step 3.4: Run tests to verify they pass**

Run: `PARALLEL_WORKERS=1 bin/rails test test/controllers/api/v1/day_passes_reschedule_test.rb`
Expected: PASS (all tests, 0 failures).

- [ ] **Step 3.5: Commit**

```bash
git add app/controllers/api/v1/day_passes_controller.rb test/controllers/api/v1/day_passes_reschedule_test.rb
git commit -m "feat(day-passes): reschedule respects the target day's daily limit"
```

---

### Task 4: Gate bundle day-scheduling (opt-in flag; admin stays ungated)

**Files:**
- Modify: `app/interactors/billing/day_pass_bundles/schedule_day.rb`
- Modify: `app/interactors/billing/day_pass_bundles/schedule_days.rb`
- Modify: `app/controllers/api/v1/day_passes_controller.rb` (`#schedule`)
- Test: `test/interactors/billing/day_pass_bundles/schedule_day_test.rb` (append)
- Test: `test/controllers/api/v1/day_passes_scheduling_test.rb` (append)
- Test: `test/controllers/api/v1/admin/members_scheduling_test.rb` (append)

- [ ] **Step 4.1: Write the failing interactor tests**

Append inside the class in `test/interactors/billing/day_pass_bundles/schedule_day_test.rb`
(reuse its `make_bundle` helper; note `@member` is created inside each test's
`ActsAsTenant.with_tenant` block, matching the file's existing style):

```ruby
  test "with enforce_daily_limit, scheduling onto a full day returns :sold_out" do
    ActsAsTenant.with_tenant(@operator) do
      @member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      bundle = make_bundle(remaining: 5)
      bundle.day_pass_type.update!(daily_limit: 1)
      date = Date.current + 3
      other = create(:user, operator: @operator, original_location: @location, current_location: @location)
      DayPass.create!(user: other, billable: other, operator: @operator, location: @location,
                      day_pass_type: bundle.day_pass_type, day: date, imported: true)

      result = Billing::DayPassBundles::ScheduleDay.call(
        user: @member, location: @location, date: date, performed_by: @member,
        enforce_daily_limit: true)

      assert_equal :sold_out, result.outcome
      assert_equal bundle.day_pass_type, result.day_pass_type
      assert_equal 5, bundle.reload.passes_remaining, "no pass may be burned on a sold-out day"
    end
  end

  test "without enforce_daily_limit (staff path), a full day still schedules" do
    ActsAsTenant.with_tenant(@operator) do
      @member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      bundle = make_bundle(remaining: 5)
      bundle.day_pass_type.update!(daily_limit: 1)
      date = Date.current + 3
      other = create(:user, operator: @operator, original_location: @location, current_location: @location)
      DayPass.create!(user: other, billable: other, operator: @operator, location: @location,
                      day_pass_type: bundle.day_pass_type, day: date, imported: true)

      result = Billing::DayPassBundles::ScheduleDay.call(
        user: @member, location: @location, date: date, performed_by: @member)

      assert_equal :scheduled, result.outcome
      assert_equal 4, bundle.reload.passes_remaining
    end
  end
```

- [ ] **Step 4.2: Run interactor tests to verify the first fails**

Run: `PARALLEL_WORKERS=1 bin/rails test test/interactors/billing/day_pass_bundles/schedule_day_test.rb`
Expected: ":sold_out" test FAILS (outcome is `:scheduled`); the "without" test passes; pre-existing tests pass.

- [ ] **Step 4.3: Add the gate to `ScheduleDay`**

In `app/interactors/billing/day_pass_bundles/schedule_day.rb`, find:

```ruby
    bundle = eligible_bundle(date, tz)
    unless bundle
      context.outcome = :no_bundle
      return
    end
```

Immediately after it, add:

```ruby
    # Daily cap (opt-in). Only member self-serve scheduling enforces the cap —
    # the staff burn-for-customer path (Api::V1::Admin::MembersController#
    # schedule_bundle_days) shares this interactor and must stay ungated:
    # staff can exceed the limit by design. Checked outside the lock; the
    # same-instant race is accepted (see spec, Concurrency).
    if context.enforce_daily_limit &&
       bundle.day_pass_type.daily_limit_reached?(day: date, location: location)
      context.day_pass_type = bundle.day_pass_type
      context.outcome = :sold_out
      return
    end
```

- [ ] **Step 4.4: Thread the flag + failed type through `ScheduleDays`**

In `app/interactors/billing/day_pass_bundles/schedule_days.rb`, change:

```ruby
        result = Billing::DayPassBundles::ScheduleDay.call(
          user: context.user, location: context.location, date: date, performed_by: context.performed_by)

        if result.outcome != :scheduled
          context.outcome     = result.outcome
```

to:

```ruby
        result = Billing::DayPassBundles::ScheduleDay.call(
          user: context.user, location: context.location, date: date, performed_by: context.performed_by,
          enforce_daily_limit: context.enforce_daily_limit)

        if result.outcome != :scheduled
          context.outcome       = result.outcome
          context.day_pass_type = result.day_pass_type # set on :sold_out, nil otherwise
```

(keep the existing `context.failed_date = ...` line below it unchanged).

- [ ] **Step 4.5: Map `:sold_out` in the member API controller**

In `app/controllers/api/v1/day_passes_controller.rb` `#schedule`, change the
`ScheduleDays.call` to pass the flag:

```ruby
    result = Billing::DayPassBundles::ScheduleDays.call(
      user: current_api_user, location: current_location,
      dates: Array(params[:dates]), performed_by: current_api_user,
      enforce_daily_limit: true)
```

and add a `when` branch to its `case result.outcome`, above `when :already_covered`:

```ruby
    when :sold_out
      render_error("#{result.day_pass_type.name.pluralize} are fully booked for #{result.failed_date.strftime('%B %e')}. Try another day.")
```

- [ ] **Step 4.6: Write the request tests (member blocked, admin not)**

Append inside the class in `test/controllers/api/v1/day_passes_scheduling_test.rb`
(its setup creates `@member` + a 5-Pack `@bundle`; the bundle's type is the local
`dpt` — reach it via `@bundle.day_pass_type`):

```ruby
  test "POST schedule returns 422 when a requested day is at the type's daily limit" do
    ActsAsTenant.with_tenant(@operator) do
      @bundle.day_pass_type.update!(daily_limit: 1)
      other = create(:user, operator: @operator, original_location: @location, current_location: @location)
      DayPass.create!(user: other, billable: other, operator: @operator, location: @location,
                      day_pass_type: @bundle.day_pass_type, day: Date.current + 1, imported: true)
    end

    post "/api/v1/day_passes/schedule",
         params: { dates: [(Date.current + 1).iso8601] }.to_json, headers: headers(@member)

    assert_response :unprocessable_entity
    assert_includes JSON.parse(response.body)["error"], "fully booked"
    assert_equal 5, @bundle.reload.passes_remaining
  end
```

Append inside the class in `test/controllers/api/v1/admin/members_scheduling_test.rb`:

```ruby
  test "admin schedules a member onto a day at the limit (staff bypass)" do
    ActsAsTenant.with_tenant(@operator) do
      @bundle.day_pass_type.update!(daily_limit: 1)
      other = create(:user, operator: @operator, original_location: @location, current_location: @location)
      DayPass.create!(user: other, billable: other, operator: @operator, location: @location,
                      day_pass_type: @bundle.day_pass_type, day: Date.current + 1, imported: true)
    end

    post "/api/v1/admin/members/#{@member.id}/schedule_bundle_days",
         params: { dates: [(Date.current + 1).iso8601] }.to_json, headers: headers

    assert_response :success
    assert_equal 4, @bundle.reload.passes_remaining
  end
```

- [ ] **Step 4.7: Run all Task 4 tests**

Run: `PARALLEL_WORKERS=1 bin/rails test test/interactors/billing/day_pass_bundles/schedule_day_test.rb test/controllers/api/v1/day_passes_scheduling_test.rb test/controllers/api/v1/admin/members_scheduling_test.rb`
Expected: PASS (0 failures) — including all pre-existing tests in those files.

- [ ] **Step 4.8: Commit**

```bash
git add app/interactors/billing/day_pass_bundles/schedule_day.rb \
        app/interactors/billing/day_pass_bundles/schedule_days.rb \
        app/controllers/api/v1/day_passes_controller.rb \
        test/interactors/billing/day_pass_bundles/schedule_day_test.rb \
        test/controllers/api/v1/day_passes_scheduling_test.rb \
        test/controllers/api/v1/admin/members_scheduling_test.rb
git commit -m "feat(day-passes): bundle day-scheduling respects daily limit (member-only, opt-in flag)"
```

---

### Task 5: Gate the web member buy flow

**Files:**
- Modify: `app/controllers/operator/day_passes_controller.rb` (in `#create`, after the `prospective_day` parse)
- Test: `test/controllers/day_passes_controller_test.rb` (append)

- [ ] **Step 5.1: Write the failing test**

Append inside the class in `test/controllers/day_passes_controller_test.rb`
(its setup logs in `users(:cowork_tahoe_member)` with StripeMock; the web form
submits the date as Rails multiparameter fields, which is what `prospective_day`
parses):

```ruby
  test "blocks self-serve purchase when the type's daily limit is reached" do
    target = Time.zone.today + 2.days
    @day_pass_type.update!(daily_limit: 1)
    other = users(:cowork_tahoe_non_member)
    ActsAsTenant.with_tenant(@user.operator) do
      DayPass.create!(user: other, billable: other, operator: @user.operator,
                      location: locations(:cowork_tahoe_location),
                      day_pass_type: @day_pass_type, day: target, imported: true)
    end

    assert_no_difference -> { DayPass.count } do
      post day_passes_path, params: { day_pass: {
        day_pass_type: @day_pass_type.id,
        "day(1i)" => target.year.to_s, "day(2i)" => target.month.to_s, "day(3i)" => target.day.to_s,
      } }, env: default_env
    end

    assert_redirected_to new_day_pass_path(day_pass_type_id: @day_pass_type.id)
    assert_includes flash[:error], "fully booked"
  end
```

- [ ] **Step 5.2: Run test to verify it fails**

Run: `PARALLEL_WORKERS=1 bin/rails test test/controllers/day_passes_controller_test.rb`
Expected: the new test FAILS (no "fully booked" flash — the purchase attempt proceeds into the interactor). Pre-existing tests pass.

- [ ] **Step 5.3: Add the gate**

In `app/controllers/operator/day_passes_controller.rb` `#create`, find the end of
the `prospective_day` parse:

```ruby
    rescue ArgumentError, TypeError
      nil
    end
```

Immediately after it (BEFORE the duplicate-purchase guard `if prospective_day && ...` block), add:

```ruby
    # Daily cap (physical capacity — e.g. 2 day offices). Member self-serve
    # only: the admin add/comp flow (Operator::Admin::DayPassesController) is
    # intentionally ungated, though its rows still count. Checked before the
    # duplicate-purchase confirm — a sold-out day is sold out regardless.
    if prospective_day && day_pass_type&.daily_limit_reached?(day: prospective_day, location: current_location)
      flash[:error] = "#{day_pass_type.name.pluralize} are fully booked for #{short_date(prospective_day)}. Try another day."
      turbo_redirect(new_day_pass_path(day_pass_type_id: day_pass_type.id))
      return
    end
```

- [ ] **Step 5.4: Run tests to verify they pass**

Run: `PARALLEL_WORKERS=1 bin/rails test test/controllers/day_passes_controller_test.rb`
Expected: PASS (all tests, 0 failures).

- [ ] **Step 5.5: Commit**

```bash
git add app/controllers/operator/day_passes_controller.rb test/controllers/day_passes_controller_test.rb
git commit -m "feat(day-passes): web self-serve purchase respects the daily limit"
```

---

### Task 6: Staff & door bypass tests (regression guards)

The bypasses are structural — no gate call sites exist on these paths. These tests
pin that behavior so a future refactor can't accidentally gate them.

**Files:**
- Test: Create `test/interactors/billing/day_passes/save_day_pass_daily_limit_test.rb`
- Test: `test/interactors/billing/day_pass_bundles/schedule_day_door_test.rb` (append — it exercises `ConsumeOnEntry` alongside scheduling)

(The admin request-level bypass is already pinned by the `schedule_bundle_days` test in
Task 4. A request test for admin `create_day_pass` is NOT feasible without heavy Stripe
scaffolding — `Billing::DayPasses::CreateDayPass` organizes `CreateStripeInvoice`, which
calls Stripe unconditionally even for $0 passes. So the staff-create bypass is pinned at
`SaveDayPass`, the pass-creation authority every staff flow goes through.)

- [ ] **Step 6.1: SaveDayPass creates past the limit (staff-create bypass)**

Create `test/interactors/billing/day_passes/save_day_pass_daily_limit_test.rb`:

```ruby
require "test_helper"

# SaveDayPass is the pass-creation authority shared by the staff/admin flows
# (web admin add/comp, mobile admin create_day_pass). It deliberately has NO
# daily-limit gate — staff can exceed the cap; gates live only at member
# self-serve entry points (see the daily-limit spec). This test pins that a
# gate never leaks into it.
class Billing::DayPasses::SaveDayPassDailyLimitTest < ActiveSupport::TestCase
  test "creates a pass past the type's daily limit (staff paths are ungated)" do
    operator = operators(:cowork_tahoe)
    location = locations(:cowork_tahoe_location)
    member   = users(:cowork_tahoe_member)
    other    = users(:cowork_tahoe_non_member)

    ActsAsTenant.with_tenant(operator) do
      dpt = DayPassType.create!(operator: operator, location: location, name: "Day Office",
                                amount_in_cents: 0, quantity: 1, available: true, daily_limit: 1)
      day = Date.current + 1
      DayPass.create!(user: other, billable: other, operator: operator, location: location,
                      day_pass_type: dpt, day: day, imported: true)

      result = Billing::DayPasses::SaveDayPass.call(
        user_id: member.id, operator: operator, location: location,
        params: { day_pass_type: dpt.id.to_s, day: day, operator_id: operator.id })

      assert result.success?, "staff pass-creation must not be blocked by the daily limit"
      assert_equal 2, dpt.day_passes.where(day: day).count
    end
  end
end
```

Note: SaveDayPass fires `after_create` member-lifecycle callbacks (welcome-drip
enrollment, activity log). If `enroll_in_welcome_drip!` errors on missing seed
data in this context, wrap the call: `member.stub(:enroll_in_welcome_drip!, nil) do ... end`.

- [ ] **Step 6.2: Door burn (`ConsumeOnEntry`) past the limit**

Open `test/interactors/billing/day_pass_bundles/schedule_day_door_test.rb` and match
its setup style (same `@operator`/`@location`/bundle helpers as `schedule_day_test.rb`).
Append:

```ruby
  test "door entry burns a bundle pass even when today is at the type's daily limit" do
    ActsAsTenant.with_tenant(@operator) do
      @member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      bundle = make_bundle(remaining: 5)
      bundle.day_pass_type.update!(daily_limit: 1)
      other = create(:user, operator: @operator, original_location: @location, current_location: @location)
      DayPass.create!(user: other, billable: other, operator: @operator, location: @location,
                      day_pass_type: bundle.day_pass_type, day: Date.current, imported: true)

      result = Billing::DayPassBundles::ConsumeOnEntry.call(user: @member, location: @location)

      assert_equal :redeemed, result.outcome, "a cap must never strand someone at the door"
      assert_equal 4, bundle.reload.passes_remaining
    end
  end
```

If `schedule_day_door_test.rb` lacks the `make_bundle` helper, copy it verbatim from
`schedule_day_test.rb`:

```ruby
  def make_bundle(qty: 5, remaining: 5, expires_at: nil, created_at: Time.current)
    dpt = DayPassType.create!(operator: @operator, location: @location, name: "#{qty}-Pack",
                              amount_in_cents: 20000, quantity: qty, available: true, visible: true)
    DayPassBundle.create!(user: @member, operator: @operator, location: @location, day_pass_type: dpt,
                          quantity_purchased: qty, passes_remaining: remaining, expires_at: expires_at,
                          created_at: created_at, purchased_at: Time.current)
  end
```

- [ ] **Step 6.3: Run the bypass tests**

Run: `PARALLEL_WORKERS=1 bin/rails test test/interactors/billing/day_passes/save_day_pass_daily_limit_test.rb test/interactors/billing/day_pass_bundles/schedule_day_door_test.rb`
Expected: PASS. (These should pass on first run — they document existing bypass behavior. If one FAILS, a gate leaked into a staff/door path: fix the gate, not the test.)

- [ ] **Step 6.4: Commit**

```bash
git add test/interactors/billing/day_passes/save_day_pass_daily_limit_test.rb \
        test/interactors/billing/day_pass_bundles/schedule_day_door_test.rb
git commit -m "test(day-passes): pin staff and door-entry bypass of the daily limit"
```

---

### Task 7: Web admin config field

**Files:**
- Modify: `app/helpers/day_pass_types_helper.rb` (both `day_pass_type_params` and `day_pass_type_update_params`)
- Modify: `app/views/operator/day_pass_types/_form.html.erb`
- Modify: `app/views/operator/day_pass_types/_edit_form.html.erb`
- Test: `test/models/day_pass_type_test.rb` already covers validation; param plumbing is verified by hand in Step 7.4 (no controller test exists for this controller; don't create test infrastructure just for one permit line)

- [ ] **Step 7.1: Permit + normalize the param**

In `app/helpers/day_pass_types_helper.rb`:

In `day_pass_type_params`, add `:daily_limit` to the permit list:

```ruby
    p = params.require(:day_pass_type).permit(:name, :amount_in_cents, :available, :visible, :always_allow_building_access, :code, :description, :included_meeting_room_minutes, :overage_rate_in_cents, :quantity, :expires_after_days, :daily_limit)
```

and before its final `p` line add:

```ruby
    # Blank form field means unlimited — normalize "" to nil so the
    # numericality validation (allow_nil) doesn't reject it.
    p[:daily_limit] = p[:daily_limit].presence
```

In `day_pass_type_update_params`, make the same two changes:

```ruby
    p = params.require(:day_pass_type).permit(:name, :amount_in_cents, :code, :description, :included_meeting_room_minutes, :overage_rate_in_cents, :quantity, :expires_after_days, :daily_limit)
```

```ruby
    p[:daily_limit] = p[:daily_limit].presence
```

- [ ] **Step 7.2: Add the field to the new form**

In `app/views/operator/day_pass_types/_form.html.erb`, after the
`expires_after_days` form-group (the one ending with
`<%= DayPassType::EXPIRATION_DISCLAIMER %></small>` + `</div>`), add:

```erb
  <div class="form-group">
    <%= form.label :daily_limit, "Max sold per day (leave blank = unlimited)" %>
    <%= form.number_field :daily_limit, class: "form-control", min: 1, step: 1, placeholder: "Unlimited" %>
    <small class="form-text text-muted">Counts every pass of this type on a given day — purchased, comped, or scheduled from a pack. Staff can always add passes past the limit.</small>
  </div>
```

- [ ] **Step 7.3: Add the same field to the edit form**

In `app/views/operator/day_pass_types/_edit_form.html.erb`, after its
`expires_after_days` form-group, add the identical block from Step 7.2.

- [ ] **Step 7.4: Verify in the browser**

```bash
bin/rails server
```

Sign in as an admin on the local dev tenant, open Day Pass Types → edit a type:
- Set "Max sold per day" to 2 → save → reopen: field shows 2.
- Clear the field → save → reopen: field is blank (unlimited); the row's `daily_limit` is NULL (`bin/rails runner 'puts DayPassType.find(<id>).daily_limit.inspect'` → `nil`).
- Set it to 0 → save → expect a validation error rendered on the form.

- [ ] **Step 7.5: Commit**

```bash
git add app/helpers/day_pass_types_helper.rb \
        app/views/operator/day_pass_types/_form.html.erb \
        app/views/operator/day_pass_types/_edit_form.html.erb
git commit -m "feat(day-passes): admin form field for per-day sales limit"
```

---

### Task 8: Full suite + PR

- [ ] **Step 8.1: Run the full test suite**

Run: `PARALLEL_WORKERS=1 bin/rails test`
Expected: 0 failures, 0 errors (same skip count as origin/main). If anything unrelated
fails, verify it also fails on a clean origin/main checkout before touching it.

- [ ] **Step 8.2: Push and open the PR**

```bash
git push -u origin feat/day-pass-daily-limit
gh pr create --repo jellyswitch/new-jellyswitch \
  --title "Day pass daily limit by type (e.g. cap Day Office sales per day)" \
  --body "$(cat <<'EOF'
## Summary
- New nullable `daily_limit` on `day_pass_types`: max passes of a type per day per location (blank = unlimited; all existing types unchanged).
- Every pass of the type on that day counts (purchased, comped, bundle-scheduled) — the cap models physical capacity (e.g. Cowork Tahoe's Day Offices).
- Blocks member self-serve at the cap: API purchase, web purchase, bundle day-scheduling (opt-in interactor flag), reschedule target day.
- Staff bypass by design: admin add/comp, admin schedule-for-member, web admin reschedule. Door burns (`ConsumeOnEntry`) are never blocked. Bypasses are pinned by regression tests.
- Config: web day-pass-type form only ("Max sold per day"). No mobile app changes.

Spec: docs/superpowers/specs/2026-07-12-day-pass-daily-limit-design.md

## Test plan
- [ ] `PARALLEL_WORKERS=1 bin/rails test` green
- [ ] Staging: set Day Office daily_limit=1, buy one pass for a day in the app, verify the second buy shows "Day Offices are fully booked for <date>"
- [ ] Staging: admin comps a pass on the same day — succeeds

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 8.3: Wait for CI, then hand off to David**

Watch CI on the PR (`gh pr checks --watch`). Do NOT merge — merging to main
auto-deploys production; David decides when. After merge, set the real limit:

```bash
heroku run --no-tty -a jellyswitch-production rails runner \
  'DayPassType.find(1343).update!(daily_limit: N)'  # Cowork Tahoe "Day Office" — David supplies N
```

---

## Out of scope (per approved spec)

- Sold-out date graying in the mobile date picker (needs a per-date availability endpoint).
- Mobile admin config field for the limit.
- Row-locking the count+create race.
- Gating web code-redemption flows (`redeem_code`/`redeem_paid`).
