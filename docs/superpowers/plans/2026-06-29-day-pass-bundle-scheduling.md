# Day Pass Bundle Scheduling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let members (and admins on their behalf) schedule a Day Pass Bundle pass for one or more future days, deducting the pass now and minting a dated `DayPass`, with self-serve cancel-before-the-day and a purchase guardrail against accidental double-buys.

**Architecture:** A scheduled day reuses the existing burn machinery: mint a bundle-sourced `DayPass(day: <future date>)`, decrement `passes_remaining`, and log a `DayPassBundleRedemption(kind: :entry)` — identical to today's `ConsumeOnEntry`, parameterized by date. The door's existing once-per-business-day burn guard and access check handle the scheduled day with no new door-time logic. Cancellation destroys the future pass, restores it to the originating bundle, and logs a new `:schedule_cancel` redemption.

**Tech Stack:** Rails (Interactor gem, ActsAsTenant, Minitest), Expo/React Native (jest), PostgreSQL.

**Spec:** `docs/superpowers/specs/2026-06-29-day-pass-bundle-scheduling-design.md`

**Repos:** backend `new-jellyswitch` (this worktree, branch `feature/day-pass-bundle-scheduling`); mobile `jellyswitch-mobile` (Phase 4 — branch from its `main`).

**Run backend tests with:** rbenv 3.3.10 active (`export PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH"`), from the repo root: `bundle exec rails test <path>`.

---

## File structure

**Backend (new-jellyswitch):**
- Create `app/interactors/billing/day_pass_bundles/schedule_day.rb` — schedule ONE date (mint+burn, all guards). The single source of truth.
- Create `app/interactors/billing/day_pass_bundles/schedule_days.rb` — batch N dates in one transaction (all-or-nothing).
- Create `app/interactors/billing/day_pass_bundles/cancel_scheduled_day.rb` — cancel a future scheduled pass, restore it.
- Modify `app/models/day_pass_bundle_redemption.rb` — add `schedule_cancel` to `KINDS`.
- Modify `app/controllers/api/v1/day_passes_controller.rb` — add `schedule`, `scheduled_days`, `cancel_scheduled`.
- Modify `app/controllers/api/v1/admin/members_controller.rb` — add `schedule_bundle_days`, `scheduled_bundle_days`, `cancel_scheduled_bundle_day`.
- Modify `config/routes.rb` — member + admin routes.
- Modify `CONTEXT.md` — rewrite the "no scheduling" sentence; add `schedule_cancel`; roster note.
- Create `docs/adr/0018-day-pass-bundle-scheduling.md`.
- Tests under `test/interactors/billing/day_pass_bundles/` and `test/controllers/api/v1/`.

**Mobile (jellyswitch-mobile):**
- Modify `src/api/client.js` — `scheduleDays`, `scheduledDays`, `cancelScheduled`.
- Create `src/utils/bundleScheduling.js` — pure helpers (`schedulableDates`, `shouldWarnBundleHolder`) + jest tests.
- Modify `src/screens/account/DayPassScreen.js` — "Schedule a day…" picker + "Scheduled days" list with cancel.
- Modify the single-pass purchase flow (same screen) — guardrail warning.

---

# Phase 1 — Backend domain (interactors)

### Task 1: Add the `schedule_cancel` redemption kind

**Files:**
- Modify: `app/models/day_pass_bundle_redemption.rb`
- Test: `test/models/day_pass_bundle_redemption_test.rb` (create if absent)

- [ ] **Step 1: Write the failing test**

```ruby
require "test_helper"

class DayPassBundleRedemptionTest < ActiveSupport::TestCase
  test "schedule_cancel is a valid kind" do
    operator = operators(:cowork_tahoe)
    ActsAsTenant.with_tenant(operator) do
      bundle = DayPassBundle.create!(
        user: users(:cowork_tahoe_admin), operator: operator,
        location: locations(:cowork_tahoe_location),
        day_pass_type: DayPassType.create!(operator: operator, location: locations(:cowork_tahoe_location),
                                           name: "5-Pack", amount_in_cents: 20000, quantity: 5, available: true, visible: true),
        quantity_purchased: 5, passes_remaining: 5,
      )
      r = bundle.redemptions.build(operator: operator, kind: "schedule_cancel", redeemed_at: Time.current)
      assert r.valid?, r.errors.full_messages.to_sentence
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rails test test/models/day_pass_bundle_redemption_test.rb -n "/schedule_cancel/"`
Expected: FAIL — `kind is not included in the list`.

- [ ] **Step 3: Add the kind**

In `app/models/day_pass_bundle_redemption.rb`, change:

```ruby
  KINDS = %w[entry guest admin_restore schedule_cancel].freeze
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rails test test/models/day_pass_bundle_redemption_test.rb -n "/schedule_cancel/"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/models/day_pass_bundle_redemption.rb test/models/day_pass_bundle_redemption_test.rb
git commit -m "feat(bundles): add schedule_cancel redemption kind"
```

---

### Task 2: `ScheduleDay` interactor — mint a dated pass from the soonest-expiring bundle

**Files:**
- Create: `app/interactors/billing/day_pass_bundles/schedule_day.rb`
- Test: `test/interactors/billing/day_pass_bundles/schedule_day_test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
require "test_helper"

class Billing::DayPassBundles::ScheduleDayTest < ActiveSupport::TestCase
  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
  end

  def make_bundle(qty: 5, remaining: 5, expires_at: nil, created_at: Time.current)
    dpt = DayPassType.create!(operator: @operator, location: @location, name: "#{qty}-Pack",
                              amount_in_cents: 20000, quantity: qty, available: true, visible: true)
    DayPassBundle.create!(user: @member, operator: @operator, location: @location, day_pass_type: dpt,
                          quantity_purchased: qty, passes_remaining: remaining, expires_at: expires_at,
                          created_at: created_at)
  end

  test "scheduling a future day mints a dated bundle-sourced pass and decrements the bundle" do
    ActsAsTenant.with_tenant(@operator) do
      @member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      bundle = make_bundle(remaining: 5)
      date = Date.current + 3

      result = Billing::DayPassBundles::ScheduleDay.call(
        user: @member, location: @location, date: date, performed_by: @member)

      assert_equal :scheduled, result.outcome
      assert_equal date, result.day_pass.day
      assert_equal @location, result.day_pass.location
      assert result.day_pass.imported, "scheduled pass must be imported (no lifecycle side effects)"
      assert_equal 4, bundle.reload.passes_remaining
      assert_equal 1, bundle.redemptions.where(kind: "entry").count
      assert_equal result.day_pass.id, bundle.redemptions.where(kind: "entry").first.day_pass_id
    end
  end

  test "draws from the soonest-expiring bundle first" do
    ActsAsTenant.with_tenant(@operator) do
      @member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      perpetual = make_bundle(remaining: 5, expires_at: nil)
      expiring   = make_bundle(remaining: 5, expires_at: 20.days.from_now)

      Billing::DayPassBundles::ScheduleDay.call(
        user: @member, location: @location, date: Date.current + 2, performed_by: @member)

      assert_equal 4, expiring.reload.passes_remaining, "should burn the soonest-expiring bundle"
      assert_equal 5, perpetual.reload.passes_remaining
    end
  end

  test "rejects a date already covered by an existing pass (no wasted pass)" do
    ActsAsTenant.with_tenant(@operator) do
      @member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      bundle = make_bundle(remaining: 5)
      date = Date.current + 4
      create(:day_pass, user: @member, billable: @member, operator: @operator, location: @location,
             day_pass_type: bundle.day_pass_type, day: date)

      result = Billing::DayPassBundles::ScheduleDay.call(
        user: @member, location: @location, date: date, performed_by: @member)

      assert_equal :already_covered, result.outcome
      assert_equal 5, bundle.reload.passes_remaining
    end
  end

  test "rejects a past date and a date beyond the horizon" do
    ActsAsTenant.with_tenant(@operator) do
      @member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      make_bundle(remaining: 5)

      past = Billing::DayPassBundles::ScheduleDay.call(
        user: @member, location: @location, date: Date.current - 1, performed_by: @member)
      assert_equal :invalid_date, past.outcome

      far = Billing::DayPassBundles::ScheduleDay.call(
        user: @member, location: @location,
        date: Date.current + Billing::DayPassBundles::ScheduleDay::HORIZON_DAYS + 1, performed_by: @member)
      assert_equal :invalid_date, far.outcome
    end
  end

  test "rejects when no passes remain" do
    ActsAsTenant.with_tenant(@operator) do
      @member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      make_bundle(remaining: 0)
      result = Billing::DayPassBundles::ScheduleDay.call(
        user: @member, location: @location, date: Date.current + 1, performed_by: @member)
      assert_equal :no_bundle, result.outcome
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rails test test/interactors/billing/day_pass_bundles/schedule_day_test.rb`
Expected: FAIL — `uninitialized constant Billing::DayPassBundles::ScheduleDay`.

- [ ] **Step 3: Write the interactor**

Create `app/interactors/billing/day_pass_bundles/schedule_day.rb`:

```ruby
class Billing::DayPassBundles::ScheduleDay
  include Interactor

  HORIZON_DAYS = 90

  delegate :user, :location, :performed_by, to: :context

  def call
    tz    = ActiveSupport::TimeZone[location&.time_zone.presence || "UTC"]
    today = Time.current.in_time_zone(tz).to_date
    date  = context.date.is_a?(String) ? Date.parse(context.date) : context.date

    if date < today || date > today + HORIZON_DAYS.days
      context.outcome = :invalid_date
      return
    end

    if already_covered?(date, tz)
      context.outcome = :already_covered
      return
    end

    bundle = eligible_bundle(date, tz)
    unless bundle
      context.outcome = :no_bundle
      return
    end

    bundle.with_lock do
      # `imported: true` skips DayPass member-lifecycle side effects — the burn
      # is the audit record (mirrors ConsumeOnEntry). NOT complimentary: the
      # pass is prepaid and must count toward door-access checks.
      day_pass = DayPass.create!(
        user:          user,
        billable:      user,
        operator:      bundle.operator,
        location:      location,
        day_pass_type: bundle.day_pass_type,
        day:           date,
        imported:      true,
      )
      bundle.burn_locked!(kind: :entry, performed_by: performed_by, day_pass: day_pass)
      context.bundle   = bundle
      context.day_pass = day_pass
      context.outcome  = :scheduled
    end
  rescue DayPassBundle::NoPassesRemaining
    context.outcome = :no_bundle
  end

  private

  # Mirrors ConsumeOnEntry's guards, scoped to the target date instead of today.
  def already_covered?(date, tz)
    return true if user.has_active_subscription?
    return true if user.has_active_lease?(location)

    day_start = date.in_time_zone(tz).beginning_of_day
    day_end   = date.in_time_zone(tz).end_of_day
    return true if user.reservations.where(cancelled: false)
                       .where(datetime_in: day_start..day_end).exists?

    user.day_passes.for_location(location).for_day(date).exists?
  end

  # Active, covers the location, not expired before the target date; soonest to
  # expire first (NULLs/perpetual last), then oldest.
  def eligible_bundle(date, tz)
    user.day_pass_bundles.active.where(location: location)
        .where("expires_at IS NULL OR expires_at > ?", date.in_time_zone(tz).end_of_day)
        .order(Arel.sql("expires_at ASC NULLS LAST, created_at ASC"))
        .first
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rails test test/interactors/billing/day_pass_bundles/schedule_day_test.rb`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add app/interactors/billing/day_pass_bundles/schedule_day.rb test/interactors/billing/day_pass_bundles/schedule_day_test.rb
git commit -m "feat(bundles): ScheduleDay interactor (dated burn, guards, soonest-expiring draw)"
```

---

### Task 3: `ScheduleDays` — batch multiple dates, all-or-nothing

**Files:**
- Create: `app/interactors/billing/day_pass_bundles/schedule_days.rb`
- Test: `test/interactors/billing/day_pass_bundles/schedule_days_test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
require "test_helper"

class Billing::DayPassBundles::ScheduleDaysTest < ActiveSupport::TestCase
  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
  end

  def make_bundle(remaining:)
    dpt = DayPassType.create!(operator: @operator, location: @location, name: "Pack",
                              amount_in_cents: 20000, quantity: 5, available: true, visible: true)
    DayPassBundle.create!(user: @member, operator: @operator, location: @location, day_pass_type: dpt,
                          quantity_purchased: 5, passes_remaining: remaining)
  end

  test "schedules every requested day and decrements once per day" do
    ActsAsTenant.with_tenant(@operator) do
      @member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      bundle = make_bundle(remaining: 5)
      dates = [Date.current + 1, Date.current + 2, Date.current + 5]

      result = Billing::DayPassBundles::ScheduleDays.call(
        user: @member, location: @location, dates: dates, performed_by: @member)

      assert_equal :scheduled, result.outcome
      assert_equal 3, result.day_passes.size
      assert_equal 2, bundle.reload.passes_remaining
      assert_equal dates.sort, @member.day_passes.bundle_sourced.where("day > ?", Date.current).pluck(:day).sort
    end
  end

  test "is all-or-nothing: one bad date rolls back the whole batch" do
    ActsAsTenant.with_tenant(@operator) do
      @member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      bundle = make_bundle(remaining: 5)
      dates = [Date.current + 1, Date.current - 1, Date.current + 3] # middle is invalid

      result = Billing::DayPassBundles::ScheduleDays.call(
        user: @member, location: @location, dates: dates, performed_by: @member)

      assert_equal :invalid_date, result.outcome
      assert_equal Date.current - 1, result.failed_date
      assert_equal 5, bundle.reload.passes_remaining, "nothing should be deducted"
      assert_equal 0, @member.day_passes.bundle_sourced.where("day > ?", Date.current).count
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rails test test/interactors/billing/day_pass_bundles/schedule_days_test.rb`
Expected: FAIL — `uninitialized constant Billing::DayPassBundles::ScheduleDays`.

- [ ] **Step 3: Write the interactor**

Create `app/interactors/billing/day_pass_bundles/schedule_days.rb`:

```ruby
class Billing::DayPassBundles::ScheduleDays
  include Interactor

  def call
    dates = Array(context.dates).map { |d| d.is_a?(String) ? Date.parse(d) : d }
    day_passes = []

    ActiveRecord::Base.transaction do
      dates.each do |date|
        result = Billing::DayPassBundles::ScheduleDay.call(
          user: context.user, location: context.location, date: date, performed_by: context.performed_by)

        if result.outcome != :scheduled
          context.outcome     = result.outcome
          context.failed_date = date
          raise ActiveRecord::Rollback
        end
        day_passes << result.day_pass
      end

      context.day_passes = day_passes
      context.outcome    = :scheduled
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rails test test/interactors/billing/day_pass_bundles/schedule_days_test.rb`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add app/interactors/billing/day_pass_bundles/schedule_days.rb test/interactors/billing/day_pass_bundles/schedule_days_test.rb
git commit -m "feat(bundles): ScheduleDays batch interactor (all-or-nothing)"
```

---

### Task 4: `CancelScheduledDay` — restore a still-future scheduled pass

**Files:**
- Create: `app/interactors/billing/day_pass_bundles/cancel_scheduled_day.rb`
- Test: `test/interactors/billing/day_pass_bundles/cancel_scheduled_day_test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
require "test_helper"

class Billing::DayPassBundles::CancelScheduledDayTest < ActiveSupport::TestCase
  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
  end

  def schedule(date)
    Billing::DayPassBundles::ScheduleDay.call(
      user: @member, location: @location, date: date, performed_by: @member).day_pass
  end

  def make_bundle(remaining: 5)
    dpt = DayPassType.create!(operator: @operator, location: @location, name: "Pack",
                              amount_in_cents: 20000, quantity: 5, available: true, visible: true)
    DayPassBundle.create!(user: @member, operator: @operator, location: @location, day_pass_type: dpt,
                          quantity_purchased: 5, passes_remaining: remaining)
  end

  test "cancelling a future scheduled day restores the pass and removes the dated pass" do
    ActsAsTenant.with_tenant(@operator) do
      @member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      bundle = make_bundle(remaining: 5)
      day_pass = schedule(Date.current + 4)
      assert_equal 4, bundle.reload.passes_remaining

      result = Billing::DayPassBundles::CancelScheduledDay.call(day_pass: day_pass, performed_by: @member)

      assert_equal :cancelled, result.outcome
      assert_equal 5, bundle.reload.passes_remaining
      assert_nil DayPass.find_by(id: day_pass.id), "the future pass is removed"
      assert_equal 1, bundle.redemptions.where(kind: "schedule_cancel").count
      assert_equal (Date.current + 4).iso8601, bundle.redemptions.where(kind: "schedule_cancel").first.guest_name
    end
  end

  test "cannot cancel once the day has started (today or past)" do
    ActsAsTenant.with_tenant(@operator) do
      @member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      bundle = make_bundle(remaining: 5)
      # Build a today-dated bundle pass directly (a started day)
      day_pass = DayPass.create!(user: @member, billable: @member, operator: @operator, location: @location,
                                 day_pass_type: bundle.day_pass_type, day: Date.current, imported: true)
      bundle.burn!(kind: :entry, performed_by: @member, day_pass: day_pass)
      assert_equal 4, bundle.reload.passes_remaining

      result = Billing::DayPassBundles::CancelScheduledDay.call(day_pass: day_pass, performed_by: @member)

      assert_equal :too_late, result.outcome
      assert_equal 4, bundle.reload.passes_remaining
      assert DayPass.find_by(id: day_pass.id), "pass is untouched"
    end
  end

  test "rejects a pass that isn't a bundle-sourced scheduled pass" do
    ActsAsTenant.with_tenant(@operator) do
      @member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      dpt = DayPassType.create!(operator: @operator, location: @location, name: "Single",
                                amount_in_cents: 4000, quantity: 1, available: true, visible: true)
      plain = create(:day_pass, user: @member, billable: @member, operator: @operator, location: @location,
                     day_pass_type: dpt, day: Date.current + 2)

      result = Billing::DayPassBundles::CancelScheduledDay.call(day_pass: plain, performed_by: @member)
      assert_equal :not_scheduled, result.outcome
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rails test test/interactors/billing/day_pass_bundles/cancel_scheduled_day_test.rb`
Expected: FAIL — `uninitialized constant Billing::DayPassBundles::CancelScheduledDay`.

- [ ] **Step 3: Write the interactor**

Create `app/interactors/billing/day_pass_bundles/cancel_scheduled_day.rb`:

```ruby
class Billing::DayPassBundles::CancelScheduledDay
  include Interactor

  def call
    day_pass   = context.day_pass
    redemption = DayPassBundleRedemption.find_by(day_pass_id: day_pass.id, kind: "entry")
    bundle     = redemption&.day_pass_bundle

    unless bundle
      context.outcome = :not_scheduled
      return
    end

    tz    = ActiveSupport::TimeZone[day_pass.location&.time_zone.presence || "UTC"]
    today = Time.current.in_time_zone(tz).to_date
    if day_pass.day <= today
      context.outcome = :too_late
      return
    end

    bundle.with_lock do
      if bundle.passes_remaining.to_i < bundle.quantity_purchased.to_i
        bundle.update!(passes_remaining: bundle.passes_remaining + 1)
      end
      bundle.redemptions.create!(
        operator: bundle.operator, kind: "schedule_cancel",
        performed_by: context.performed_by, guest_name: day_pass.day.iso8601, redeemed_at: Time.current)
      redemption.update!(day_pass: nil) # detach before destroying the pass
      day_pass.destroy!
    end

    context.bundle  = bundle
    context.outcome = :cancelled
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rails test test/interactors/billing/day_pass_bundles/cancel_scheduled_day_test.rb`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add app/interactors/billing/day_pass_bundles/cancel_scheduled_day.rb test/interactors/billing/day_pass_bundles/cancel_scheduled_day_test.rb
git commit -m "feat(bundles): CancelScheduledDay interactor (restore future pass)"
```

---

### Task 5: Door regression — a scheduled pass opens the door on its day without double-burning

**Files:**
- Test: `test/interactors/billing/day_pass_bundles/schedule_day_door_test.rb`

This proves Approach A's core claim: no new door logic needed.

- [ ] **Step 1: Write the failing test**

```ruby
require "test_helper"

class Billing::DayPassBundles::ScheduleDayDoorTest < ActiveSupport::TestCase
  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
  end

  test "a pass scheduled for today is already covered at the door — no second burn" do
    ActsAsTenant.with_tenant(@operator) do
      member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      dpt = DayPassType.create!(operator: @operator, location: @location, name: "Pack",
                                amount_in_cents: 20000, quantity: 5, available: true, visible: true)
      bundle = DayPassBundle.create!(user: member, operator: @operator, location: @location,
                                     day_pass_type: dpt, quantity_purchased: 5, passes_remaining: 5)

      # Schedule "today" (boundary): mints today's dated pass, burns one.
      Billing::DayPassBundles::ScheduleDay.call(
        user: member, location: @location, date: Date.current, performed_by: member)
      assert_equal 4, bundle.reload.passes_remaining

      # Door entry today runs ConsumeOnEntry; Guard 4 sees the existing pass → no burn.
      door = Billing::DayPassBundles::ConsumeOnEntry.call(user: member, location: @location)
      assert_equal :already_covered, door.outcome
      assert_equal 4, bundle.reload.passes_remaining, "door must not burn a second pass"
    end
  end
end
```

- [ ] **Step 2: Run it**

Run: `bundle exec rails test test/interactors/billing/day_pass_bundles/schedule_day_door_test.rb`
Expected: PASS immediately (no production change — this is a guard test confirming existing behavior). If it FAILS, stop and reconcile `ScheduleDay` with `ConsumeOnEntry`'s Guard 4 before continuing.

- [ ] **Step 3: Commit**

```bash
git add test/interactors/billing/day_pass_bundles/schedule_day_door_test.rb
git commit -m "test(bundles): scheduled-today pass is covered at the door, no double-burn"
```

---

# Phase 2 — Backend API

### Task 6: Member endpoints — schedule, list, cancel

**Files:**
- Modify: `config/routes.rb` (the `resources :day_passes` block near line 112)
- Modify: `app/controllers/api/v1/day_passes_controller.rb`
- Test: `test/controllers/api/v1/day_passes_scheduling_test.rb`

- [ ] **Step 1: Add the routes**

In `config/routes.rb`, replace the existing member `day_passes` block:

```ruby
      resources :day_passes, only: [:create] do
        collection do
          post :redeem_today
          post :schedule
          get  :scheduled_days
        end
        member do
          post :cancel_scheduled
        end
      end
```

(Preserve any other entries already inside that block — add `schedule`, `scheduled_days`, `cancel_scheduled` alongside `redeem_today`.)

- [ ] **Step 2: Write the failing request test**

```ruby
require "test_helper"

class Api::V1::DayPassesSchedulingTest < ActionDispatch::IntegrationTest
  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @member = nil
    ActsAsTenant.with_tenant(@operator) do
      @member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      dpt = DayPassType.create!(operator: @operator, location: @location, name: "5-Pack",
                                amount_in_cents: 20000, quantity: 5, available: true, visible: true)
      @bundle = DayPassBundle.create!(user: @member, operator: @operator, location: @location,
                                      day_pass_type: dpt, quantity_purchased: 5, passes_remaining: 5)
    end
  end

  def headers(user)
    token = JWT.encode({ user_id: user.id, exp: 30.days.from_now.to_i }, Rails.application.secret_key_base, "HS256")
    { "Authorization" => "Bearer #{token}", "X-Operator-Subdomain" => @operator.subdomain, "Content-Type" => "application/json" }
  end

  test "POST schedule reserves the requested future days" do
    dates = [(Date.current + 1).iso8601, (Date.current + 3).iso8601]
    post "/api/v1/day_passes/schedule", params: { dates: dates }.to_json, headers: headers(@member)
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "scheduled", body["status"]
    assert_equal dates.sort, body["scheduled_days"].sort
    assert_equal 3, body["passes_remaining"]
  end

  test "GET scheduled_days lists only upcoming bundle days" do
    Billing::DayPassBundles::ScheduleDay.call(user: @member, location: @location, date: Date.current + 2, performed_by: @member)
    get "/api/v1/day_passes/scheduled_days", headers: headers(@member)
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 1, body.size
    assert_equal (Date.current + 2).iso8601, body.first["day"]
    assert body.first["id"].present?
  end

  test "POST cancel_scheduled restores the pass" do
    dp = Billing::DayPassBundles::ScheduleDay.call(user: @member, location: @location, date: Date.current + 2, performed_by: @member).day_pass
    post "/api/v1/day_passes/#{dp.id}/cancel_scheduled", headers: headers(@member)
    assert_response :success
    assert_equal "cancelled", JSON.parse(response.body)["status"]
    assert_equal 5, @bundle.reload.passes_remaining
  end

  test "a member cannot cancel another member's scheduled day" do
    other = nil
    ActsAsTenant.with_tenant(@operator) do
      other = create(:user, operator: @operator, original_location: @location, current_location: @location)
    end
    dp = Billing::DayPassBundles::ScheduleDay.call(user: @member, location: @location, date: Date.current + 2, performed_by: @member).day_pass
    post "/api/v1/day_passes/#{dp.id}/cancel_scheduled", headers: headers(other)
    assert_response :not_found
  end
end
```

- [ ] **Step 3: Run it (fails — actions undefined → routing error)**

Run: `bundle exec rails test test/controllers/api/v1/day_passes_scheduling_test.rb`
Expected: FAIL — no route / unknown action.

- [ ] **Step 4: Add the controller actions**

In `app/controllers/api/v1/day_passes_controller.rb`, add these actions and a private helper:

```ruby
  def schedule
    result = Billing::DayPassBundles::ScheduleDays.call(
      user: current_api_user, location: current_location,
      dates: Array(params[:dates]), performed_by: current_api_user)

    case result.outcome
    when :scheduled
      render json: {
        status: "scheduled",
        scheduled_days: result.day_passes.map { |dp| dp.day.iso8601 },
        passes_remaining: remaining_passes,
      }
    when :already_covered
      render_error("You're already set for #{result.failed_date.strftime('%B %e')}.")
    when :invalid_date
      render_error("That date can't be scheduled.")
    else # :no_bundle / :no_passes
      render_error("You don't have enough day passes left.")
    end
  end

  def scheduled_days
    tz    = ActiveSupport::TimeZone[current_location&.time_zone.presence || "UTC"]
    today = Time.current.in_time_zone(tz).to_date
    passes = current_api_user.day_passes.bundle_sourced
               .for_location(current_location).where("day > ?", today).order(:day)
    render json: passes.map { |dp| { id: dp.id, day: dp.day.iso8601, date: dp.day.strftime("%B %e, %Y") } }
  end

  def cancel_scheduled
    day_pass = current_api_user.day_passes.find(params[:id])
    result = Billing::DayPassBundles::CancelScheduledDay.call(day_pass: day_pass, performed_by: current_api_user)
    case result.outcome
    when :cancelled
      render json: { status: "cancelled", passes_remaining: remaining_passes }
    when :too_late
      render_error("That day has already started — it can't be cancelled.")
    else
      render_error("That scheduled day couldn't be found.")
    end
  end

  private

  def remaining_passes
    current_api_user.day_pass_bundles.active.where(location: current_location).sum(:passes_remaining)
  end
```

Note: `current_api_user.day_passes.find` returns 404 for another member's pass (it's scoped to the caller) — that satisfies the ownership test.

- [ ] **Step 5: Run it (passes)**

Run: `bundle exec rails test test/controllers/api/v1/day_passes_scheduling_test.rb`
Expected: PASS (4 tests).

- [ ] **Step 6: Commit**

```bash
git add config/routes.rb app/controllers/api/v1/day_passes_controller.rb test/controllers/api/v1/day_passes_scheduling_test.rb
git commit -m "feat(api): member bundle-day schedule/list/cancel endpoints"
```

---

### Task 7: Admin endpoints — schedule/list/cancel on a member's behalf

**Files:**
- Modify: `config/routes.rb` (admin namespace, near `post 'members/:id/create_day_pass'` ~line 213)
- Modify: `app/controllers/api/v1/admin/members_controller.rb`
- Test: `test/controllers/api/v1/admin/members_scheduling_test.rb`

- [ ] **Step 1: Add the routes**

In the admin namespace block of `config/routes.rb`, alongside `create_day_pass`:

```ruby
        post 'members/:id/schedule_bundle_days',  to: 'members#schedule_bundle_days'
        get  'members/:id/scheduled_bundle_days', to: 'members#scheduled_bundle_days'
        post 'members/:member_id/scheduled_bundle_days/:id/cancel', to: 'members#cancel_scheduled_bundle_day'
```

- [ ] **Step 2: Write the failing request test**

```ruby
require "test_helper"

class Api::V1::Admin::MembersSchedulingTest < ActionDispatch::IntegrationTest
  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @admin    = users(:cowork_tahoe_admin)
    ActsAsTenant.with_tenant(@operator) do
      @member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      dpt = DayPassType.create!(operator: @operator, location: @location, name: "5-Pack",
                                amount_in_cents: 20000, quantity: 5, available: true, visible: true)
      @bundle = DayPassBundle.create!(user: @member, operator: @operator, location: @location,
                                      day_pass_type: dpt, quantity_purchased: 5, passes_remaining: 5)
    end
  end

  def headers
    token = JWT.encode({ user_id: @admin.id, exp: 30.days.from_now.to_i }, Rails.application.secret_key_base, "HS256")
    { "Authorization" => "Bearer #{token}", "X-Operator-Subdomain" => @operator.subdomain, "Content-Type" => "application/json" }
  end

  test "admin schedules days for a member" do
    post "/api/v1/admin/members/#{@member.id}/schedule_bundle_days",
         params: { dates: [(Date.current + 1).iso8601] }.to_json, headers: headers
    assert_response :success
    assert_equal "scheduled", JSON.parse(response.body)["status"]
    assert_equal 4, @bundle.reload.passes_remaining
  end

  test "admin lists then cancels a member's scheduled day" do
    dp = Billing::DayPassBundles::ScheduleDay.call(user: @member, location: @location, date: Date.current + 2, performed_by: @member).day_pass

    get "/api/v1/admin/members/#{@member.id}/scheduled_bundle_days", headers: headers
    assert_response :success
    assert_equal dp.id, JSON.parse(response.body).first["id"]

    post "/api/v1/admin/members/#{@member.id}/scheduled_bundle_days/#{dp.id}/cancel", headers: headers
    assert_response :success
    assert_equal 5, @bundle.reload.passes_remaining
  end
end
```

- [ ] **Step 3: Run it (fails)**

Run: `bundle exec rails test test/controllers/api/v1/admin/members_scheduling_test.rb`
Expected: FAIL — unknown action / route.

- [ ] **Step 4: Add the controller actions**

In `app/controllers/api/v1/admin/members_controller.rb`, add. Use the same tenant/location resolution the existing `create_day_pass` action uses (match `current_tenant` / how it resolves the member's location — mirror the existing action's pattern in this file):

```ruby
  def schedule_bundle_days
    member = current_tenant.users.find(params[:id])
    location = member.current_location || current_location
    result = Billing::DayPassBundles::ScheduleDays.call(
      user: member, location: location, dates: Array(params[:dates]), performed_by: current_api_user)

    if result.outcome == :scheduled
      render json: { status: "scheduled", scheduled_days: result.day_passes.map { |dp| dp.day.iso8601 },
                     passes_remaining: member.day_pass_bundles.active.where(location: location).sum(:passes_remaining) }
    else
      render_error("Could not schedule those days (#{result.outcome}).")
    end
  end

  def scheduled_bundle_days
    member = current_tenant.users.find(params[:id])
    location = member.current_location || current_location
    tz = ActiveSupport::TimeZone[location&.time_zone.presence || "UTC"]
    today = Time.current.in_time_zone(tz).to_date
    passes = member.day_passes.bundle_sourced.for_location(location).where("day > ?", today).order(:day)
    render json: passes.map { |dp| { id: dp.id, day: dp.day.iso8601, date: dp.day.strftime("%B %e, %Y") } }
  end

  def cancel_scheduled_bundle_day
    member = current_tenant.users.find(params[:member_id])
    day_pass = member.day_passes.find(params[:id])
    result = Billing::DayPassBundles::CancelScheduledDay.call(day_pass: day_pass, performed_by: current_api_user)
    if result.outcome == :cancelled
      render json: { status: "cancelled" }
    else
      render_error("Could not cancel that day (#{result.outcome}).")
    end
  end
```

If `render_error` / `current_tenant` / `current_location` aren't available in this controller, match the helpers the existing actions in this same file use (check `create_day_pass`).

- [ ] **Step 5: Run it (passes)**

Run: `bundle exec rails test test/controllers/api/v1/admin/members_scheduling_test.rb`
Expected: PASS (2 tests).

- [ ] **Step 6: Commit**

```bash
git add config/routes.rb app/controllers/api/v1/admin/members_controller.rb test/controllers/api/v1/admin/members_scheduling_test.rb
git commit -m "feat(api): admin schedule/list/cancel bundle days for a member"
```

---

# Phase 3 — Documentation

### Task 8: Update CONTEXT.md and add ADR 0018

**Files:**
- Modify: `CONTEXT.md` (Day Pass Bundle section)
- Create: `docs/adr/0018-day-pass-bundle-scheduling.md`

- [ ] **Step 1: Rewrite the "no scheduling" sentence in CONTEXT.md**

In the "Day Pass Bundle" bullet about burn-on-entry, replace:

> There is **no scheduling** — passes are not assigned to future dates.

with:

> Passes may also be **scheduled** for a future date: scheduling mints a dated `DayPass` now and decrements the bundle immediately (a confirmed reservation), reusing the same burn machinery — so on that day the door opens via the normal access check with no second burn. A member (or an admin on their behalf) can schedule one or many upcoming days, draws come from the **soonest-expiring** bundle, and a still-future scheduled day can be **cancelled** self-serve (the pass is restored). See `docs/adr/0018-day-pass-bundle-scheduling.md`.

- [ ] **Step 2: Add `schedule_cancel` to the redemption-kind list in CONTEXT.md**

In the "Redemption ledger" bullet, change the kinds list to include `schedule_cancel` (reverses a cancelled future schedule, restoring the pass), e.g.: `kind: entry | guest | admin_restore | schedule_cancel`.

- [ ] **Step 3: Create the ADR**

Create `docs/adr/0018-day-pass-bundle-scheduling.md`:

```markdown
# 0018 — Day Pass Bundle scheduling (reserve-ahead via dated DayPass)

## Status
Accepted (2026-06-29)

## Context
Bundle redemption was today-only (`ConsumeOnEntry`), but members who wanted an
upcoming day bought a separate single pass for that date on top of their pack
and double-paid (confirmed live; recurring). ADR 0017 established that a
member-initiated redemption is the *same burn* as a door entry.

## Decision
A scheduled day is a normal burn, dated to a future day: mint a bundle-sourced
`DayPass(day: <future date>)`, decrement `passes_remaining`, and log a
`DayPassBundleRedemption(kind: :entry)` — no new model, no new door logic (the
existing once-per-business-day guard and access check handle the day).

- **Deduct now** (confirmed reservation), not at entry.
- **Self-serve cancel before the day starts** restores the pass to the
  originating bundle and logs a new `:schedule_cancel` redemption; once the day
  begins it is spent (`admin_restore` still covers genuine mistakes).
- Draw from the **soonest-expiring** bundle, then oldest.
- **90-day** horizon; reject past dates, already-covered dates, and dates past a
  bundle's expiration.
- **Guests stay today-only** (out of scope).
- A **purchase guardrail** warns a bundle-holder buying a single pass for a day
  their pack could cover.

## Consequences
- Revenue recognition is unchanged (ADR 0009): scheduling spends prepaid value,
  $0 at schedule time; bundle-sourced passes stay out of day-pass revenue.
- Expiration rules unchanged (ADR 0008); a scheduled date may not exceed the
  drawn bundle's expiration.
- Operators gain advance visibility: scheduled days appear on the daily roster.
```

- [ ] **Step 4: Commit**

```bash
git add CONTEXT.md docs/adr/0018-day-pass-bundle-scheduling.md
git commit -m "docs: bundle scheduling — CONTEXT.md + ADR 0018"
```

---

# Phase 4 — Mobile (jellyswitch-mobile)

> Branch `feature/bundle-scheduling` off `jellyswitch-mobile` `main`. Run jest with `npx jest <path>`.

### Task 9: API client methods

**Files:**
- Modify: `src/api/client.js` (the object that defines `redeemToday` at line ~220)

- [ ] **Step 1: Add the methods**

Next to `redeemToday`, add:

```javascript
  scheduleDays: (dates) => client.post('/day_passes/schedule', { dates }),
  scheduledDays: () => client.get('/day_passes/scheduled_days'),
  cancelScheduled: (id) => client.post(`/day_passes/${id}/cancel_scheduled`),
```

- [ ] **Step 2: Commit**

```bash
git add src/api/client.js
git commit -m "feat(api-client): bundle scheduling methods"
```

---

### Task 10: Pure scheduling helpers + jest tests

**Files:**
- Create: `src/utils/bundleScheduling.js`
- Test: `tests/utils/bundle-scheduling.test.js`

- [ ] **Step 1: Write the failing test**

```javascript
import { isSchedulable, shouldWarnBundleHolder, HORIZON_DAYS } from '../../src/utils/bundleScheduling';

const iso = (d) => d.toISOString().slice(0, 10);
const todayISO = '2026-06-29';

describe('isSchedulable', () => {
  test('rejects past dates and today, accepts within horizon', () => {
    expect(isSchedulable('2026-06-28', todayISO)).toBe(false);
    expect(isSchedulable('2026-06-29', todayISO)).toBe(false); // today uses redeem-now
    expect(isSchedulable('2026-06-30', todayISO)).toBe(true);
  });

  test('rejects beyond the horizon', () => {
    const far = new Date('2026-06-29');
    far.setDate(far.getDate() + HORIZON_DAYS + 1);
    expect(isSchedulable(iso(far), todayISO)).toBe(false);
  });

  test('rejects a date already in scheduledDays', () => {
    expect(isSchedulable('2026-07-01', todayISO, ['2026-07-01'])).toBe(false);
  });
});

describe('shouldWarnBundleHolder', () => {
  test('warns when buying a single for a coverable future date while holding passes', () => {
    expect(shouldWarnBundleHolder({ passesRemaining: 3, date: '2026-07-02', today: todayISO })).toBe(true);
  });
  test('no warning with zero passes', () => {
    expect(shouldWarnBundleHolder({ passesRemaining: 0, date: '2026-07-02', today: todayISO })).toBe(false);
  });
  test('no warning for past/invalid dates', () => {
    expect(shouldWarnBundleHolder({ passesRemaining: 3, date: '2026-06-28', today: todayISO })).toBe(false);
  });
});
```

- [ ] **Step 2: Run it (fails)**

Run: `npx jest tests/utils/bundle-scheduling.test.js`
Expected: FAIL — cannot find module.

- [ ] **Step 3: Write the helpers**

Create `src/utils/bundleScheduling.js`:

```javascript
// Pure date helpers for bundle-pass scheduling. No React, no native deps, so
// they're unit-testable. Dates are ISO 'YYYY-MM-DD' strings compared
// lexicographically (valid for ISO dates).
export const HORIZON_DAYS = 90;

function addDaysISO(iso, n) {
  const d = new Date(`${iso}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}

// A date a member may SCHEDULE: strictly after today (today uses redeem-now),
// within the horizon, and not already scheduled.
export function isSchedulable(dateISO, todayISO, scheduledISO = []) {
  if (!dateISO || !todayISO) return false;
  if (dateISO <= todayISO) return false;
  if (dateISO > addDaysISO(todayISO, HORIZON_DAYS)) return false;
  if (scheduledISO.includes(dateISO)) return false;
  return true;
}

// Whether to warn a member who is about to BUY a single pass for a future day
// their bundle could cover instead.
export function shouldWarnBundleHolder({ passesRemaining, date, today }) {
  if (!passesRemaining || passesRemaining <= 0) return false;
  if (!date || date < today) return false;
  return true;
}
```

- [ ] **Step 4: Run it (passes)**

Run: `npx jest tests/utils/bundle-scheduling.test.js`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/utils/bundleScheduling.js tests/utils/bundle-scheduling.test.js
git commit -m "feat(scheduling): pure date/guardrail helpers + tests"
```

---

### Task 11: "Schedule a day…" + "Scheduled days" list on DayPassScreen

**Files:**
- Modify: `src/screens/account/DayPassScreen.js`

Reuse the existing date-picker component this screen already uses for the single-pass purchase, and the existing `Card`/`Button` components. Add below the existing "Use a pass for today" button.

- [ ] **Step 1: Add state + handlers**

Near the existing `redeemToday` handler, add:

```javascript
  const [scheduled, setScheduled] = useState([]);
  const [picked, setPicked] = useState([]); // ISO strings the user selected

  const loadScheduled = async () => {
    try {
      const res = await dayPassBundlesAPI.scheduledDays();
      setScheduled(res.data || []);
    } catch (e) {}
  };
  // call loadScheduled() in the screen's existing useFocusEffect/refresh path

  const handleSchedule = async () => {
    if (!picked.length) return;
    try {
      const res = await dayPassBundlesAPI.scheduleDays(picked);
      Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
      Alert.alert('Scheduled', `You're set for ${picked.length} day(s). ${res.data.passes_remaining} passes left.`);
      setPicked([]);
      loadScheduled();
      // refresh the bundle/passes-remaining view the screen already shows
    } catch (e) {
      Alert.alert('Error', e?.response?.data?.error || 'Could not schedule those days.');
    }
  };

  const handleCancelScheduled = async (id, dateLabel) => {
    Alert.alert('Cancel scheduled day', `Cancel ${dateLabel}? The pass goes back to your pack.`, [
      { text: 'Keep it', style: 'cancel' },
      { text: 'Cancel day', style: 'destructive', onPress: async () => {
        try {
          await dayPassBundlesAPI.cancelScheduled(id);
          Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
          loadScheduled();
        } catch (e) {
          Alert.alert('Error', e?.response?.data?.error || 'Could not cancel that day.');
        }
      } },
    ]);
  };
```

- [ ] **Step 2: Add the UI (below "Use a pass for today")**

```jsx
{/* Schedule upcoming days from the bundle */}
<Card>
  <Text style={[typography.label, { marginBottom: spacing.xs }]}>SCHEDULE A DAY</Text>
  <Text style={[typography.bodySmall, { marginBottom: spacing.sm }]}>
    Coming in another day? Use a bundle pass for an upcoming date instead of buying a new one.
  </Text>
  {/* Reuse the same date picker the single-pass purchase uses; gate selectable
      dates with isSchedulable(dateISO, todayISO, scheduled.map(s => s.day)). On
      pick, toggle the ISO date in `picked`. */}
  <Button title={picked.length ? `Schedule ${picked.length} day(s)` : 'Pick a day'} onPress={handleSchedule} disabled={!picked.length} />
</Card>

{scheduled.length > 0 && (
  <Card>
    <Text style={[typography.label, { marginBottom: spacing.xs }]}>SCHEDULED DAYS</Text>
    {scheduled.map((s) => (
      <View key={s.id} style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', paddingVertical: spacing.sm }}>
        <Text style={typography.body}>{s.date}</Text>
        <Pressable onPress={() => handleCancelScheduled(s.id, s.date)} hitSlop={8}>
          <Ionicons name="close-circle-outline" size={22} color={colors.textMuted} />
        </Pressable>
      </View>
    ))}
  </Card>
)}
```

Wire `isSchedulable` (import from `../../utils/bundleScheduling`) into the picker's selectable-date predicate, with `todayISO` from the device date.

- [ ] **Step 3: Verify in the app**

Run the app against staging (`__DEV__` build points at staging). As a member holding a bundle: open Day Passes → schedule a future day → confirm it appears under "Scheduled days" and "passes remaining" dropped → cancel it → confirm the pass returns. (Use `preview`/device per the team's mobile run flow.)

- [ ] **Step 4: Commit**

```bash
git add src/screens/account/DayPassScreen.js
git commit -m "feat(day-passes): schedule upcoming bundle days + scheduled-days list with cancel"
```

---

### Task 12: Purchase guardrail (stop the accidental double-buy)

**Files:**
- Modify: `src/screens/account/DayPassScreen.js` (the single-pass purchase handler)

- [ ] **Step 1: Gate the purchase**

In the existing single-day-pass purchase handler, before charging, when a future date is selected:

```javascript
import { shouldWarnBundleHolder } from '../../utils/bundleScheduling';

// `passesRemaining` and `selectedDateISO` already exist on this screen.
if (shouldWarnBundleHolder({ passesRemaining, date: selectedDateISO, today: todayISO })) {
  Alert.alert(
    'Use a pass instead?',
    `You already have ${passesRemaining} day pass(es) in your pack. Use one for ${selectedDateLabel} instead of buying another?`,
    [
      { text: 'Buy anyway', style: 'destructive', onPress: () => proceedWithPurchase() },
      { text: 'Use a pass', onPress: async () => { await dayPassBundlesAPI.scheduleDays([selectedDateISO]); loadScheduled(); } },
    ],
  );
  return; // wait for the user's choice
}
proceedWithPurchase();
```

(`proceedWithPurchase()` = the existing charge call extracted into a function so both branches can reach it.)

- [ ] **Step 2: Verify in the app**

As a member with bundle passes, start buying a single pass for a future date → confirm the "Use a pass instead?" prompt → "Use a pass" schedules it (no charge) and it appears under Scheduled days; "Buy anyway" still charges.

- [ ] **Step 3: Commit**

```bash
git add src/screens/account/DayPassScreen.js
git commit -m "feat(day-passes): guardrail — warn bundle-holders buying a single for a coverable day"
```

---

### Task 13: Admin schedule-on-behalf UI

**Files:**
- Modify: the admin member-detail screen that already has "create day pass" (find it: `grep -rn "create_day_pass\|createDayPass" src/`)

- [ ] **Step 1: Add an admin API client method**

In `src/api/client.js` admin section:

```javascript
  scheduleBundleDaysForMember: (memberId, dates) => client.post(`/admin/members/${memberId}/schedule_bundle_days`, { dates }),
  scheduledBundleDaysForMember: (memberId) => client.get(`/admin/members/${memberId}/scheduled_bundle_days`),
  cancelScheduledBundleDay: (memberId, id) => client.post(`/admin/members/${memberId}/scheduled_bundle_days/${id}/cancel`),
```

- [ ] **Step 2: Add a "Schedule bundle day(s)" control** to the admin member-detail screen mirroring Task 11's picker, calling the admin methods above, and a list with cancel. Reuse the same picker + `isSchedulable` gating.

- [ ] **Step 3: Verify in the app** as an admin: schedule a day for a member, see it listed, cancel it.

- [ ] **Step 4: Commit**

```bash
git add src/api/client.js <admin screen path>
git commit -m "feat(admin): schedule/cancel bundle days for a member"
```

---

## Self-review checklist (run before handoff)

- **Spec coverage:** scope (member multi-day + admin) → Tasks 2,3,6,7,11,13; deduct-now → Task 2; cancel-before-day → Tasks 4,6,7,11; guardrail → Tasks 10,12; soonest-expiring → Task 2; 90-day horizon → Tasks 2,10; guests out of scope → not implemented (correct); door/revenue/roster → Task 5 + scheduled_days listing; docs → Task 8. ✓
- **Type/name consistency:** outcomes (`:scheduled`, `:already_covered`, `:invalid_date`, `:no_bundle`, `:cancelled`, `:too_late`, `:not_scheduled`) used identically across interactors, controllers, tests. `dayPassBundlesAPI` method names match between Task 9 and Tasks 11/12. `isSchedulable`/`shouldWarnBundleHolder`/`HORIZON_DAYS` match Task 10 across Tasks 11/12. ✓
- **Open follow-ups (not blockers):** operator-configurable horizon, guest-day scheduling, first-class reschedule — listed in the spec's "future work".

## Final verification

- [ ] Backend full suites green: `bundle exec rails test` (Minitest) and the project's RSpec run, plus a clean boot.
- [ ] Mobile: `npx jest` green.
- [ ] Open one backend PR (`feature/day-pass-bundle-scheduling`) and one mobile PR; mobile change is pure JS → OTA-able on runtime 7.1.0 after merge.
