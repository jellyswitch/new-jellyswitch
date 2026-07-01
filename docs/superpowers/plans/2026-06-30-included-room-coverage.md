# Included-Room Coverage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Booking an included room commits day-pass coverage for its date — confirm before booking, block if uncovered — reusing a spare (cancelled-booking) pass → a bundle pass → a purchase, with meeting-room overage still charged against the covering pass.

**Architecture:** A read-only `CoverageState` classifies (member, room, date). Coverage is committed by small guarded organizer steps that run before `ChargeAtBooking` (authoritative for the captured amount): `ReuseCoveragePass`, the existing `RedeemBundlePass`, and `BuyCoverageDayPass`, followed by `EnforceCoverage` which blocks an uncovered included booking. The silent controller auto-buy is deleted. A `day_passes.reservation_id` link makes "leftover from a cancelled booking" an exact query.

**Tech Stack:** Rails (Interactor gem, ActsAsTenant, Minitest), Expo/React Native (jest), PostgreSQL, Stripe.

**Spec:** `docs/superpowers/specs/2026-06-30-included-room-coverage-design.md`
**Base branch:** `feature/included-room-coverage` (off the staging line — this extends the not-yet-merged reservation-billing redesign).
**Run backend tests:** `export PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH"` then `bundle exec rails test <path>` from the repo root. Run the billing suites **single-process** (`PARALLEL_WORKERS=1`) — the parallel runner deadlocks on `with_lock` against the shared test DB.

---

## File structure

**Backend (new-jellyswitch):**
- Migration `db/migrate/*_add_reservation_to_day_passes.rb` — nullable `day_passes.reservation_id`.
- `app/models/day_pass.rb` — `belongs_to :reservation, optional: true`; scope for reusable passes.
- Create `app/services/billing/reservations/coverage_state.rb` — classify (member, room, date). Read-only.
- Create `app/interactors/billing/reservations/reuse_coverage_pass.rb` — re-date a spare pass (guarded by `use_existing_pass`).
- Create `app/interactors/billing/reservations/buy_coverage_day_pass.rb` — buy a pass (guarded by `buy_day_pass`), rollback-safe.
- Create `app/interactors/billing/reservations/enforce_coverage.rb` — block an uncovered included booking.
- Modify `app/interactors/billing/reservations/create_room_reservation.rb` — add the three steps + enforcement before `ChargeAtBooking`.
- Modify `app/interactors/billing/reservations/redeem_bundle_pass.rb` — stamp `reservation_id` on the minted pass (so cancel/reuse are consistent).
- Modify `app/controllers/api/v1/reservations_controller.rb` — remove the silent auto-buy; forward the decision flags; enforce via `CoverageState`.
- Modify the Phase-7 reservation-eligibility endpoint — add `coverage` (state + overage) to its payload.
- Modify `app/interactors/cancel_reservation.rb` — sibling-booking guard on bundle restore.
- Docs: `docs/adr/0019-included-room-commits-coverage.md`, `CONTEXT.md`.

**Mobile (jellyswitch-mobile, `feature/included-room-coverage` off the staging mobile line):**
- `src/utils/coverageConfirm.js` — pure mapping `(coverageState, overageCents) → {title, body, confirmLabel, flag}` + jest.
- The reserve confirm screen — call the eligibility preview, show the variant, send the flag.

**Web:** the reserve confirmation flow — same three/four variants.

---

# Phase 1 — Data model + CoverageState

### Task 1: `day_passes.reservation_id` link

**Files:**
- Create: `db/migrate/20260630000001_add_reservation_to_day_passes.rb`
- Modify: `app/models/day_pass.rb`
- Test: `test/models/day_pass_test.rb`

- [ ] **Step 1: Write the migration**

```ruby
class AddReservationToDayPasses < ActiveRecord::Migration[7.1]
  def change
    add_reference :day_passes, :reservation, null: true, foreign_key: { on_delete: :nullify }, index: true
  end
end
```

- [ ] **Step 2: Migrate**

Run: `bundle exec rails db:migrate`
Expected: adds the column + index; `db/schema.rb` updated.

- [ ] **Step 3: Write the failing test**

```ruby
require "test_helper"

class DayPassReservationLinkTest < ActiveSupport::TestCase
  test "a day pass optionally belongs to a reservation" do
    operator = operators(:cowork_tahoe)
    ActsAsTenant.with_tenant(operator) do
      loc  = locations(:cowork_tahoe_location)
      user = create(:user, operator: operator, original_location: loc, current_location: loc)
      dpt  = create(:day_pass_type, operator: operator, location: loc, included_meeting_room_minutes: 60)
      room = create(:room, operator: operator, location: loc, hourly_rate_in_cents: 0, include_with_day_pass: true)
      res  = create(:reservation, user: user, room: room, minutes: 60)
      dp   = create(:day_pass, user: user, billable: user, operator: operator, location: loc,
                    day_pass_type: dpt, day: Date.current, reservation: res)
      assert_equal res, dp.reload.reservation
    end
  end
end
```

- [ ] **Step 4: Add the association + reusable scope**

In `app/models/day_pass.rb`, add:

```ruby
  belongs_to :reservation, optional: true

  # A purchased (non-bundle-sourced) pass bought for a booking that was then
  # cancelled — still unused and today-or-future, so it can be re-dated onto a
  # new booking (ADR 0019). `not_bundle_sourced` excludes bundle mints, which
  # have their own lifecycle.
  scope :reusable_coverage, ->(today) {
    not_bundle_sourced
      .where("day >= ?", today)
      .joins(:reservation)
      .where(reservations: { cancelled: true })
  }
```

- [ ] **Step 5: Run test**

Run: `PARALLEL_WORKERS=1 bundle exec rails test test/models/day_pass_test.rb -n "/belongs_to a reservation/"`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add db/migrate/20260630000001_add_reservation_to_day_passes.rb db/schema.rb app/models/day_pass.rb test/models/day_pass_test.rb
git commit -m "feat(day-pass): optional reservation link + reusable_coverage scope"
```

---

### Task 2: `CoverageState` classifier

**Files:**
- Create: `app/services/billing/reservations/coverage_state.rb`
- Test: `test/services/billing/reservations/coverage_state_test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
require "test_helper"

class Billing::Reservations::CoverageStateTest < ActiveSupport::TestCase
  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
  end

  def included_room
    create(:room, operator: @operator, location: @location, hourly_rate_in_cents: 0, include_with_day_pass: true)
  end

  def dpt(minutes: 60, cents: 4000)
    create(:day_pass_type, operator: @operator, location: @location,
           included_meeting_room_minutes: minutes, amount_in_cents: cents, available: true, visible: true)
  end

  test "paid room is not_applicable" do
    ActsAsTenant.with_tenant(@operator) do
      user = create(:user, operator: @operator, original_location: @location, current_location: @location)
      room = create(:room, operator: @operator, location: @location, hourly_rate_in_cents: 5000, include_with_day_pass: false)
      state = Billing::Reservations::CoverageState.for(user: user, room: room, date: Date.current + 2, location: @location)
      assert_equal :not_applicable, state.outcome
    end
  end

  test "existing day pass for the date is already_covered" do
    ActsAsTenant.with_tenant(@operator) do
      user = create(:user, operator: @operator, original_location: @location, current_location: @location)
      date = Date.current + 2
      create(:day_pass, user: user, billable: user, operator: @operator, location: @location, day_pass_type: dpt, day: date)
      state = Billing::Reservations::CoverageState.for(user: user, room: included_room, date: date, location: @location)
      assert_equal :already_covered, state.outcome
    end
  end

  test "a cancelled-booking leftover pass is reusable, preferred over a bundle" do
    ActsAsTenant.with_tenant(@operator) do
      user = create(:user, operator: @operator, original_location: @location, current_location: @location)
      room = included_room
      # a spare purchased pass from a cancelled booking, dated to another future day
      spare_res = create(:reservation, user: user, room: room, minutes: 60, cancelled: true)
      spare = create(:day_pass, user: user, billable: user, operator: @operator, location: @location,
                     day_pass_type: dpt, day: Date.current + 5, reservation: spare_res)
      # also owns a bundle
      bt = dpt
      DayPassBundle.create!(user: user, operator: @operator, location: @location, day_pass_type: bt,
                            quantity_purchased: 5, passes_remaining: 5, purchased_at: Time.current)

      state = Billing::Reservations::CoverageState.for(user: user, room: room, date: Date.current + 3, location: @location)
      assert_equal :reusable_pass, state.outcome
      assert_equal spare.id, state.reusable_pass.id
    end
  end

  test "an active bundle (no spare) is bundle_available" do
    ActsAsTenant.with_tenant(@operator) do
      user = create(:user, operator: @operator, original_location: @location, current_location: @location)
      DayPassBundle.create!(user: user, operator: @operator, location: @location, day_pass_type: dpt,
                            quantity_purchased: 5, passes_remaining: 3, purchased_at: Time.current)
      state = Billing::Reservations::CoverageState.for(user: user, room: included_room, date: Date.current + 3, location: @location)
      assert_equal :bundle_available, state.outcome
      assert_equal 3, state.passes_remaining
    end
  end

  test "no coverage is needs_purchase and carries the suggested type + price" do
    ActsAsTenant.with_tenant(@operator) do
      user = create(:user, operator: @operator, original_location: @location, current_location: @location)
      t = dpt(cents: 4000)
      state = Billing::Reservations::CoverageState.for(user: user, room: included_room, date: Date.current + 3, location: @location)
      assert_equal :needs_purchase, state.outcome
      assert_equal t.id, state.day_pass_type.id
      assert_equal 4000, state.amount_cents
    end
  end
end
```

- [ ] **Step 2: Run it (fails)**

Run: `PARALLEL_WORKERS=1 bundle exec rails test test/services/billing/reservations/coverage_state_test.rb`
Expected: FAIL — `uninitialized constant Billing::Reservations::CoverageState`.

- [ ] **Step 3: Write the classifier**

Create `app/services/billing/reservations/coverage_state.rb`:

```ruby
# Read-only classification of a member's day-pass coverage for booking an
# INCLUDED room on a given date (ADR 0019). Single source of truth shared by
# the eligibility preview and the booking-time enforcement.
class Billing::Reservations::CoverageState
  Result = Struct.new(:outcome, :passes_remaining, :bundle, :day_pass_type, :amount_cents, :reusable_pass,
                      keyword_init: true)

  def self.for(user:, room:, date:, location:)
    new(user: user, room: room, date: date.to_date, location: location).call
  end

  def initialize(user:, room:, date:, location:)
    @user = user
    @room = room
    @date = date
    @location = location
  end

  def call
    return Result.new(outcome: :not_applicable) unless included_room?
    return Result.new(outcome: :already_covered) if already_covered?

    if (spare = reusable_pass)
      return Result.new(outcome: :reusable_pass, reusable_pass: spare)
    end

    if (bundle = active_bundle)
      return Result.new(outcome: :bundle_available, bundle: bundle,
                        passes_remaining: active_bundles.sum(:passes_remaining))
    end

    type = suggested_day_pass_type
    Result.new(outcome: :needs_purchase, day_pass_type: type, amount_cents: type&.amount_in_cents)
  end

  private

  attr_reader :user, :room, :date, :location

  def included_room?
    room.hourly_rate_in_cents.to_i.zero? && room.include_with_day_pass?
  end

  # Mirrors reservations_controller#needs_cov (centralized).
  def already_covered?
    user.has_active_subscription? ||
      user.has_active_lease?(location) ||
      user.day_passes.for_location(location).for_day(date).exists? ||
      user.admin_or_manager?(location) ||
      user.superadmin?
  end

  # A purchased pass from a cancelled booking, still today-or-future, not the
  # requested date (that would be already_covered). Prefer the soonest such day.
  def reusable_pass
    user.day_passes.reusable_coverage(today)
        .where(location: location)
        .where.not(day: date)
        .order(:day)
        .first
  end

  def active_bundles
    user.day_pass_bundles.active.where(location: location)
  end

  # Soonest-expiring, then oldest (matches ADR 0018 draw order).
  def active_bundle
    active_bundles.order(Arel.sql("expires_at ASC NULLS LAST, created_at ASC")).first
  end

  # The same SKU the old silent auto-buy chose.
  def suggested_day_pass_type
    scope = DayPassType.where(operator_id: location.operator_id)
                       .where("location_id = ? OR location_id IS NULL", location.id)
                       .available.where(visible: true).where("amount_in_cents > 0")
                       .where.not("name ILIKE ?", "%office%")
    scope.where(default_for_room_booking: true).first || scope.order(:amount_in_cents).first
  end

  def today
    ActiveSupport::TimeZone[location&.time_zone.presence || "UTC"].today
  end
end
```

- [ ] **Step 4: Run it (passes)**

Run: `PARALLEL_WORKERS=1 bundle exec rails test test/services/billing/reservations/coverage_state_test.rb`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add app/services/billing/reservations/coverage_state.rb test/services/billing/reservations/coverage_state_test.rb
git commit -m "feat(reservations): CoverageState classifier (ADR 0019)"
```

---

# Phase 2 — Coverage-commit organizer steps

### Task 3: `RedeemBundlePass` stamps `reservation_id`

**Files:**
- Modify: `app/interactors/billing/reservations/redeem_bundle_pass.rb`
- Test: `test/interactors/billing/reservations/redeem_bundle_pass_test.rb` (extend existing if present)

- [ ] **Step 1: Write the failing test** (add to the existing test file, or create it)

```ruby
require "test_helper"

class Billing::Reservations::RedeemBundlePassReservationLinkTest < ActiveSupport::TestCase
  test "the minted bundle pass is linked to the reservation" do
    operator = operators(:cowork_tahoe); location = locations(:cowork_tahoe_location)
    ActsAsTenant.with_tenant(operator) do
      user = create(:user, operator: operator, original_location: location, current_location: location)
      room = create(:room, operator: operator, location: location, hourly_rate_in_cents: 0, include_with_day_pass: true)
      dpt  = create(:day_pass_type, operator: operator, location: location, included_meeting_room_minutes: 60)
      DayPassBundle.create!(user: user, operator: operator, location: location, day_pass_type: dpt,
                            quantity_purchased: 5, passes_remaining: 5, purchased_at: Time.current)
      res  = create(:reservation, user: user, room: room, minutes: 60, datetime_in: (Date.current + 2).to_time + 9.hours)

      result = Billing::Reservations::RedeemBundlePass.call(reservation: res, user: user, use_bundle_pass: true)
      assert_equal :redeemed, result.outcome
      assert_equal res.id, result.bundle_redemption_day_pass.reservation_id
    end
  end
end
```

- [ ] **Step 2: Run it (fails)**

Run: `PARALLEL_WORKERS=1 bundle exec rails test test/interactors/billing/reservations/redeem_bundle_pass_test.rb -n "/linked to the reservation/"`
Expected: FAIL — `reservation_id` is nil.

- [ ] **Step 3: Add `reservation:` to the mint**

In `redeem_bundle_pass.rb`, the `DayPass.create!(...)` call, add `reservation: reservation,`:

```ruby
      day_pass = DayPass.create!(
        user:          user,
        billable:      user,
        operator:      bundle.operator,
        location:      location,
        day_pass_type: bundle.day_pass_type,
        day:           day,
        imported:      true,
        reservation:   reservation,
      )
```

- [ ] **Step 4: Run it (passes)**

Run: `PARALLEL_WORKERS=1 bundle exec rails test test/interactors/billing/reservations/redeem_bundle_pass_test.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/interactors/billing/reservations/redeem_bundle_pass.rb test/interactors/billing/reservations/redeem_bundle_pass_test.rb
git commit -m "feat(reservations): link the bundle-minted pass to its reservation"
```

---

### Task 4: `ReuseCoveragePass` — re-date a spare pass

**Files:**
- Create: `app/interactors/billing/reservations/reuse_coverage_pass.rb`
- Test: `test/interactors/billing/reservations/reuse_coverage_pass_test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
require "test_helper"

class Billing::Reservations::ReuseCoveragePassTest < ActiveSupport::TestCase
  setup do
    @operator = operators(:cowork_tahoe); @location = locations(:cowork_tahoe_location)
  end

  test "re-dates a spare pass onto the reservation and links it" do
    ActsAsTenant.with_tenant(@operator) do
      user = create(:user, operator: @operator, original_location: @location, current_location: @location)
      room = create(:room, operator: @operator, location: @location, hourly_rate_in_cents: 0, include_with_day_pass: true)
      dpt  = create(:day_pass_type, operator: @operator, location: @location, included_meeting_room_minutes: 60)
      old_res = create(:reservation, user: user, room: room, minutes: 60, cancelled: true)
      spare = create(:day_pass, user: user, billable: user, operator: @operator, location: @location,
                     day_pass_type: dpt, day: Date.current + 5, reservation: old_res)
      new_res = create(:reservation, user: user, room: room, minutes: 60,
                       datetime_in: (Date.current + 3).to_time + 9.hours)

      result = Billing::Reservations::ReuseCoveragePass.call(
        reservation: new_res, user: user, use_existing_pass: true, coverage_pass: spare)

      assert_equal :reused, result.outcome
      assert_equal (Date.current + 3), spare.reload.day
      assert_equal new_res.id, spare.reservation_id
    end
  end

  test "no-op unless use_existing_pass" do
    ActsAsTenant.with_tenant(@operator) do
      user = create(:user, operator: @operator, original_location: @location, current_location: @location)
      res = create(:reservation, user: user, room: create(:room, operator: @operator, location: @location, hourly_rate_in_cents: 0, include_with_day_pass: true), minutes: 60)
      result = Billing::Reservations::ReuseCoveragePass.call(reservation: res, user: user, use_existing_pass: false)
      assert_nil result.outcome
    end
  end
end
```

- [ ] **Step 2: Run it (fails)**

Run: `PARALLEL_WORKERS=1 bundle exec rails test test/interactors/billing/reservations/reuse_coverage_pass_test.rb`
Expected: FAIL — constant missing.

- [ ] **Step 3: Write the interactor**

Create `app/interactors/billing/reservations/reuse_coverage_pass.rb`:

```ruby
# Re-date a member's leftover purchased pass (from a cancelled booking) onto
# this reservation's date instead of charging again (ADR 0019). Guarded by the
# client's `use_existing_pass` decision. The pass keeps its invoice + type, so
# the paid purchase and its included-minutes/overage carry over. Runs before
# ChargeAtBooking so the pass zeroes the base charge.
class Billing::Reservations::ReuseCoveragePass
  include Interactor

  delegate :reservation, :user, :use_existing_pass, :coverage_pass, to: :context

  def call
    return unless use_existing_pass
    return unless reservation&.persisted?

    pass = coverage_pass || pick_spare
    return unless pass

    @previous_day = pass.day
    @previous_reservation_id = pass.reservation_id
    pass.update!(day: reservation.datetime_in.to_date, reservation: reservation)
    context.coverage_pass = pass
    context.outcome = :reused
  end

  # Undo the re-date if a later organizer step fails.
  def rollback
    pass = context.coverage_pass
    return unless pass && @previous_day
    pass.update!(day: @previous_day, reservation_id: @previous_reservation_id)
  rescue => e
    Rails.logger.error("ReuseCoveragePass rollback failed for reservation #{reservation&.id}: #{e.class}: #{e.message}")
  end

  private

  def pick_spare
    today = ActiveSupport::TimeZone[reservation.room.location.time_zone.presence || "UTC"].today
    user.day_passes.reusable_coverage(today).where(location: reservation.room.location)
        .where.not(day: reservation.datetime_in.to_date).order(:day).first
  end
end
```

- [ ] **Step 4: Run it (passes)**

Run: `PARALLEL_WORKERS=1 bundle exec rails test test/interactors/billing/reservations/reuse_coverage_pass_test.rb`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add app/interactors/billing/reservations/reuse_coverage_pass.rb test/interactors/billing/reservations/reuse_coverage_pass_test.rb
git commit -m "feat(reservations): ReuseCoveragePass — re-date a spare pass (ADR 0019)"
```

---

### Task 5: `BuyCoverageDayPass` — buy a pass, rollback-safe

**Files:**
- Create: `app/interactors/billing/reservations/buy_coverage_day_pass.rb`
- Test: `test/interactors/billing/reservations/buy_coverage_day_pass_test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
require "test_helper"

class Billing::Reservations::BuyCoverageDayPassTest < ActiveSupport::TestCase
  setup do
    @operator = operators(:cowork_tahoe); @location = locations(:cowork_tahoe_location)
  end

  test "buys a day pass for the reservation date and links it" do
    ActsAsTenant.with_tenant(@operator) do
      user = create(:user, operator: @operator, original_location: @location, current_location: @location)
      room = create(:room, operator: @operator, location: @location, hourly_rate_in_cents: 0, include_with_day_pass: true)
      type = create(:day_pass_type, operator: @operator, location: @location,
                    included_meeting_room_minutes: 60, amount_in_cents: 4000, available: true, visible: true)
      res  = create(:reservation, user: user, room: room, minutes: 60,
                    datetime_in: (Date.current + 3).to_time + 9.hours)

      result = Billing::Reservations::BuyCoverageDayPass.call(
        reservation: res, user: user, buy_day_pass: true, day_pass_type: type, location: @location)

      assert_equal :bought, result.outcome
      dp = user.day_passes.for_day(Date.current + 3).first
      assert dp, "a day pass exists for the reservation date"
      assert_equal res.id, dp.reservation_id
    end
  end

  test "no-op unless buy_day_pass" do
    ActsAsTenant.with_tenant(@operator) do
      user = create(:user, operator: @operator, original_location: @location, current_location: @location)
      res = create(:reservation, user: user, room: create(:room, operator: @operator, location: @location, hourly_rate_in_cents: 0, include_with_day_pass: true), minutes: 60)
      result = Billing::Reservations::BuyCoverageDayPass.call(reservation: res, user: user, buy_day_pass: false)
      assert_nil result.outcome
    end
  end
end
```

- [ ] **Step 2: Run it (fails)**

Run: `PARALLEL_WORKERS=1 bundle exec rails test test/interactors/billing/reservations/buy_coverage_day_pass_test.rb`
Expected: FAIL — constant missing.

- [ ] **Step 3: Write the interactor**

Create `app/interactors/billing/reservations/buy_coverage_day_pass.rb`. Reuses `Billing::DayPasses::CreateDayPass` (which charges via `ChargeDayPassInvoice`), then stamps the reservation link. Runs before `ChargeAtBooking`.

```ruby
class Billing::Reservations::BuyCoverageDayPass
  include Interactor

  delegate :reservation, :user, :buy_day_pass, :day_pass_type, :location, to: :context

  def call
    return unless buy_day_pass
    return unless reservation&.persisted?

    date = reservation.datetime_in.to_date
    type = day_pass_type || suggested_type
    context.fail!(message: "You need a day pass to book that date, but none is available.") unless type

    result = Billing::DayPasses::CreateDayPass.call(
      params: { day: date, day_pass_type: type.id, operator: location.operator },
      operator: location.operator, location: location, user_id: user.id, out_of_band: user.out_of_band?,
    )
    context.fail!(message: "Couldn't purchase day pass: #{result.message}") unless result.success?

    pass = user.day_passes.for_location(location).for_day(date).order(created_at: :desc).first
    pass&.update!(reservation: reservation)
    context.coverage_pass = pass
    context.outcome = :bought
  end

  # If a later organizer step fails, void/refund the just-bought pass so a
  # never-committed booking doesn't strand a paid pass.
  def rollback
    pass = context.coverage_pass
    return unless pass && context.outcome == :bought
    Billing::DayPasses::RefundDayPass.call(day_pass: pass) if defined?(Billing::DayPasses::RefundDayPass)
    pass.destroy
  rescue => e
    Rails.logger.error("BuyCoverageDayPass rollback failed for reservation #{reservation&.id}: #{e.class}: #{e.message}")
    Honeybadger.notify(e) rescue nil
  end

  private

  def suggested_type
    Billing::Reservations::CoverageState.for(
      user: user, room: reservation.room, date: reservation.datetime_in.to_date, location: location
    ).day_pass_type
  end
end
```

> Implementer note: confirm whether a `Billing::DayPasses::RefundDayPass` (or equivalent) exists; if not, the rollback should void the day-pass invoice using the same primitive the refunds flow uses (`grep -rn "refund" app/interactors/billing/day_passes app/services/billing` and mirror it). If no refund primitive exists yet, scope rollback to destroy the local pass + its unpaid invoice and log a Honeybadger note for manual reconciliation — and flag this as DONE_WITH_CONCERNS.

- [ ] **Step 4: Run it (passes)**

Run: `PARALLEL_WORKERS=1 bundle exec rails test test/interactors/billing/reservations/buy_coverage_day_pass_test.rb`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add app/interactors/billing/reservations/buy_coverage_day_pass.rb test/interactors/billing/reservations/buy_coverage_day_pass_test.rb
git commit -m "feat(reservations): BuyCoverageDayPass — buy coverage, rollback-safe (ADR 0019)"
```

---

### Task 6: `EnforceCoverage` — block an uncovered included booking

**Files:**
- Create: `app/interactors/billing/reservations/enforce_coverage.rb`
- Test: `test/interactors/billing/reservations/enforce_coverage_test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
require "test_helper"

class Billing::Reservations::EnforceCoverageTest < ActiveSupport::TestCase
  setup { @operator = operators(:cowork_tahoe); @location = locations(:cowork_tahoe_location) }

  test "fails when an included booking has no coverage committed" do
    ActsAsTenant.with_tenant(@operator) do
      user = create(:user, operator: @operator, original_location: @location, current_location: @location)
      room = create(:room, operator: @operator, location: @location, hourly_rate_in_cents: 0, include_with_day_pass: true)
      res  = create(:reservation, user: user, room: room, minutes: 60, datetime_in: (Date.current + 3).to_time + 9.hours)
      result = Billing::Reservations::EnforceCoverage.call(reservation: res, user: user, location: @location)
      assert result.failure?
      assert_match(/day pass/i, result.message)
    end
  end

  test "passes for a paid room" do
    ActsAsTenant.with_tenant(@operator) do
      user = create(:user, operator: @operator, original_location: @location, current_location: @location)
      room = create(:room, operator: @operator, location: @location, hourly_rate_in_cents: 5000, include_with_day_pass: false)
      res  = create(:reservation, user: user, room: room, minutes: 60, datetime_in: (Date.current + 3).to_time + 9.hours)
      result = Billing::Reservations::EnforceCoverage.call(reservation: res, user: user, location: @location)
      assert result.success?
    end
  end

  test "passes once a pass covers the date" do
    ActsAsTenant.with_tenant(@operator) do
      user = create(:user, operator: @operator, original_location: @location, current_location: @location)
      room = create(:room, operator: @operator, location: @location, hourly_rate_in_cents: 0, include_with_day_pass: true)
      dpt  = create(:day_pass_type, operator: @operator, location: @location, included_meeting_room_minutes: 60)
      create(:day_pass, user: user, billable: user, operator: @operator, location: @location, day_pass_type: dpt, day: Date.current + 3)
      res  = create(:reservation, user: user, room: room, minutes: 60, datetime_in: (Date.current + 3).to_time + 9.hours)
      result = Billing::Reservations::EnforceCoverage.call(reservation: res, user: user, location: @location)
      assert result.success?
    end
  end
end
```

- [ ] **Step 2: Run it (fails)**

Run: `PARALLEL_WORKERS=1 bundle exec rails test test/interactors/billing/reservations/enforce_coverage_test.rb`
Expected: FAIL — constant missing.

- [ ] **Step 3: Write the interactor** — runs AFTER the reuse/burn/buy steps; re-classifies and blocks if still uncovered.

Create `app/interactors/billing/reservations/enforce_coverage.rb`:

```ruby
# Guardrail (ADR 0019): an INCLUDED-room booking must have day-pass coverage for
# its date. Runs after the reuse/burn/buy steps; if the room is included and the
# member is still not covered (nobody reused/burned/bought), fail the booking so
# the organizer rolls it back — the controller surfaces this as a 422. Paid rooms
# and already-covered dates pass through untouched.
class Billing::Reservations::EnforceCoverage
  include Interactor

  delegate :reservation, :user, :location, to: :context

  def call
    room = reservation.room
    return if room.hourly_rate_in_cents.to_i > 0 || !room.include_with_day_pass?

    date = reservation.datetime_in.to_date
    state = Billing::Reservations::CoverageState.for(user: user, room: room, date: date, location: location)
    return if state.outcome == :already_covered # a step just committed a pass, or they were covered

    context.fail!(
      message: "This room needs a day pass for #{date.strftime('%b %-d')}. Use a pass or buy one to book it.",
    )
  end
end
```

- [ ] **Step 4: Run it (passes)**

Run: `PARALLEL_WORKERS=1 bundle exec rails test test/interactors/billing/reservations/enforce_coverage_test.rb`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add app/interactors/billing/reservations/enforce_coverage.rb test/interactors/billing/reservations/enforce_coverage_test.rb
git commit -m "feat(reservations): EnforceCoverage — block uncovered included bookings (ADR 0019)"
```

---

### Task 7: Wire the steps into the organizer

**Files:**
- Modify: `app/interactors/billing/reservations/create_room_reservation.rb`

- [ ] **Step 1: Add the steps before `ChargeAtBooking`**

```ruby
  organize(
    Billing::Reservations::SaveRoomReservation,
    Billing::Reservations::ChargeCredits,
    Billing::Reservations::ReuseCoveragePass,
    Billing::Reservations::RedeemBundlePass,
    Billing::Reservations::BuyCoverageDayPass,
    Billing::Reservations::EnforceCoverage,
    Billing::Reservations::ChargeAtBooking,
    Reservations::ScheduleUpcomingReservationReminder,
    CreateNotificationsAsync,
    SendAdminNotificationForPaidRoom,
    Billing::Reservations::ScheduleReservationEmails
  )
```

Each coverage step is a no-op unless its decision flag is set; `EnforceCoverage` blocks if none committed. Order matters: reuse → burn → buy → enforce → charge (so the pass exists when `ChargeAtBooking` prices room + overage, and enforcement sees any just-committed pass).

- [ ] **Step 2: Run the interactor suites to confirm no regression**

Run: `PARALLEL_WORKERS=1 bundle exec rails test test/interactors/billing/reservations/`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add app/interactors/billing/reservations/create_room_reservation.rb
git commit -m "feat(reservations): commit coverage before charge (reuse/burn/buy/enforce)"
```

---

# Phase 3 — Controller + eligibility preview

### Task 8: Controller — drop the silent auto-buy, forward decision flags

**Files:**
- Modify: `app/controllers/api/v1/reservations_controller.rb` (the `create` action, ~lines 44–123)
- Test: `test/controllers/api/v1/reservations_coverage_test.rb`

- [ ] **Step 1: Write the failing request test**

```ruby
require "test_helper"

class Api::V1::ReservationsCoverageTest < ActionDispatch::IntegrationTest
  setup do
    @operator = operators(:cowork_tahoe); @location = locations(:cowork_tahoe_location)
    ActsAsTenant.with_tenant(@operator) do
      @member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      @room = create(:room, operator: @operator, location: @location, hourly_rate_in_cents: 0, include_with_day_pass: true)
      @type = create(:day_pass_type, operator: @operator, location: @location,
                     included_meeting_room_minutes: 120, amount_in_cents: 4000, available: true, visible: true,
                     default_for_room_booking: true)
    end
  end

  def headers(user)
    token = JWT.encode({ user_id: user.id, exp: 30.days.from_now.to_i }, Rails.application.secret_key_base, "HS256")
    { "Authorization" => "Bearer #{token}", "X-Operator-Subdomain" => @operator.subdomain, "Content-Type" => "application/json" }
  end

  def body(extra = {})
    { reservation: { room_id: @room.id, datetime_in: (Date.current + 3).to_time.change(hour: 9).iso8601, minutes: 60 }.merge(extra) }.to_json
  end

  test "included room with NO coverage decision is blocked (422), no silent auto-buy" do
    assert_no_difference -> { @member.day_passes.count } do
      post "/api/v1/reservations", params: body, headers: headers(@member)
    end
    assert_response :unprocessable_entity
    assert_equal 0, Reservation.where(user: @member, cancelled: false).count
  end

  test "buy_day_pass books it and creates a linked day pass" do
    ActsAsTenant.with_tenant(@operator) do
      @member.update!(payment_method: "card") if @member.respond_to?(:payment_method)
    end
    post "/api/v1/reservations", params: body(buy_day_pass: true), headers: headers(@member)
    assert_response :created
    dp = @member.day_passes.for_day(Date.current + 3).first
    assert dp
    assert_equal Reservation.where(user: @member).order(:id).last.id, dp.reservation_id
  end
end
```

> Implementer note: the buy path charges via Stripe (`ChargeDayPassInvoice`) — if the test env can't hit Stripe, stub `Billing::DayPasses::CreateDayPass` to succeed and mint the pass (mirror how existing reservation request tests stub capture). Keep the *behavioral* assertions (422 with no decision; pass created + linked with a decision).

- [ ] **Step 2: Run it (fails — currently auto-buys instead of 422)**

Run: `PARALLEL_WORKERS=1 bundle exec rails test test/controllers/api/v1/reservations_coverage_test.rb`
Expected: FAIL — the current controller auto-buys (pass count changes; response 201).

- [ ] **Step 3: Replace the `needs_cov` block**

In `create`, delete the entire `needs_cov` block (from the `needs_cov = ...` computation through the `CreateDayPass` call). Replace with flag parsing + forwarding:

```ruby
    use_bundle_pass   = ActiveModel::Type::Boolean.new.cast(params.dig(:reservation, :use_bundle_pass))
    use_existing_pass = ActiveModel::Type::Boolean.new.cast(params.dig(:reservation, :use_existing_pass))
    buy_day_pass      = ActiveModel::Type::Boolean.new.cast(params.dig(:reservation, :buy_day_pass))

    coverage = Billing::Reservations::CoverageState.for(user: user, room: room, date: date, location: location)
    # For :needs_purchase, resolve the SKU the buy step will use.
    coverage_day_pass_type = coverage.day_pass_type
```

Then pass the flags + type into the organizer call:

```ruby
    result = Billing::Reservations::CreateRoomReservation.call(
      reservation_params: { datetime_in: datetime_in, hours: minutes / 60.0, minutes: minutes, room: room, amenity_ids: amenity_ids },
      user: current_api_user,
      location: current_location,
      day_pass_charge_info: day_pass_charge_info,
      subscription_charge_info: subscription_charge_info,
      use_bundle_pass: use_bundle_pass,
      use_existing_pass: use_existing_pass,
      buy_day_pass: buy_day_pass,
      day_pass_type: coverage_day_pass_type,
    )
```

The organizer's `EnforceCoverage` returns a failed result when an included, uncovered booking arrives with no decision; the existing `else render_error(result.error ...)` branch already surfaces it — change its status to 422:

```ruby
    if result.success?
      render json: reservation_json(result.reservation), status: :created
    else
      render_error(result.error || 'Booking failed', status: :unprocessable_entity)
    end
```

(If `render_error` doesn't take a status, add an optional `status:` param defaulting to the current one.)

- [ ] **Step 4: Run it (passes)**

Run: `PARALLEL_WORKERS=1 bundle exec rails test test/controllers/api/v1/reservations_coverage_test.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/api/v1/reservations_controller.rb test/controllers/api/v1/reservations_coverage_test.rb
git commit -m "feat(api): enforce included-room coverage; drop silent auto-buy (ADR 0019)"
```

---

### Task 9: Eligibility preview payload (coverage + overage)

**Files:**
- Modify: the Phase-7 reservation-eligibility endpoint (find it: `git grep -ln "eligibility\|access_window\|use 1 pass\|bundle_eligible" app/controllers/api`)
- Test: extend that endpoint's request test.

- [ ] **Step 1: Write the failing test** asserting the endpoint returns a `coverage` object with `state` and `overage_in_cents` for a room+date+minutes. (Mirror the endpoint's existing test setup; assert `state == "needs_purchase"` with the SKU price for an uncovered member, and `overage_in_cents` computed via `user.day_pass_reservation_charge_info` for the covering type.)

- [ ] **Step 2: Run it (fails).**

- [ ] **Step 3: Add to the endpoint's JSON:**

```ruby
    coverage = Billing::Reservations::CoverageState.for(user: current_api_user, room: room, date: date, location: current_location)
    covering_type = case coverage.outcome
                    when :bundle_available then coverage.bundle&.day_pass_type
                    when :reusable_pass   then coverage.reusable_pass&.day_pass_type
                    when :needs_purchase  then coverage.day_pass_type
                    else current_api_user.day_passes.for_day(date).first&.day_pass_type
                    end
    overage = Billing::Reservations::OveragePreview.cents(
      user: current_api_user, location: current_location, date: date, minutes: minutes,
      day_pass_type: covering_type, reservation_id: nil,
    )
    json[:coverage] = {
      state: coverage.outcome,
      passes_remaining: coverage.passes_remaining,
      day_pass_amount_in_cents: coverage.amount_cents,
      reusable_from_date: coverage.reusable_pass&.day&.iso8601,
      overage_in_cents: overage,
    }
```

`OveragePreview` (Task 10) computes the prospective overage. Confirm the endpoint receives `minutes` + `date`; add params if needed.

- [ ] **Step 4: Run it (passes). Step 5: Commit** `feat(api): expose coverage state + overage in reservation eligibility`.

---

# Phase 4 — Overage preview helper

### Task 10: `OveragePreview` (prospective overage for a covering type)

**Files:**
- Create: `app/services/billing/reservations/overage_preview.rb`
- Test: `test/services/billing/reservations/overage_preview_test.rb`

- [ ] **Step 1: Write the failing test** — a 90-min booking against a 60-min-included type, with 0 other minutes that day, at a location overage rate of $60/hr, returns 30 min → $30 (3000 cents). And returns 0 when minutes ≤ included, and 0 for an unlimited (`has_meeting_room_limit? == false`) type.

```ruby
require "test_helper"

class Billing::Reservations::OveragePreviewTest < ActiveSupport::TestCase
  setup { @operator = operators(:cowork_tahoe); @location = locations(:cowork_tahoe_location) }

  test "prospective overage against a limited type" do
    ActsAsTenant.with_tenant(@operator) do
      @location.update!(overage_rate_in_cents: 6000) # $60/hr
      user = create(:user, operator: @operator, original_location: @location, current_location: @location)
      type = create(:day_pass_type, operator: @operator, location: @location, included_meeting_room_minutes: 60)
      cents = Billing::Reservations::OveragePreview.cents(
        user: user, location: @location, date: Date.current + 3, minutes: 90, day_pass_type: type, reservation_id: nil)
      assert_equal 3000, cents # 30 min over × $60/hr
    end
  end

  test "no overage within allowance or for unlimited type" do
    ActsAsTenant.with_tenant(@operator) do
      user = create(:user, operator: @operator, original_location: @location, current_location: @location)
      limited = create(:day_pass_type, operator: @operator, location: @location, included_meeting_room_minutes: 120)
      assert_equal 0, Billing::Reservations::OveragePreview.cents(user: user, location: @location, date: Date.current + 3, minutes: 60, day_pass_type: limited, reservation_id: nil)
      unlimited = create(:day_pass_type, operator: @operator, location: @location, included_meeting_room_minutes: nil)
      assert_equal 0, Billing::Reservations::OveragePreview.cents(user: user, location: @location, date: Date.current + 3, minutes: 999, day_pass_type: unlimited, reservation_id: nil)
    end
  end
end
```

- [ ] **Step 2: Run it (fails).**

- [ ] **Step 3: Write the service** — mirrors `ChargeCalculator#day_pass_overage_cents`, but parameterized by a (possibly not-yet-existing) type:

```ruby
class Billing::Reservations::OveragePreview
  # Prospective meeting-room overage (cents) for a booking of `minutes` on
  # `date`, drawn against `day_pass_type`'s included minutes net of the member's
  # other include_with_day_pass bookings that day. Mirrors
  # ChargeCalculator#day_pass_overage_cents so the quote matches the capture.
  def self.cents(user:, location:, date:, minutes:, day_pass_type:, reservation_id:)
    return 0 unless day_pass_type&.has_meeting_room_limit?
    allotment = day_pass_type.included_meeting_room_minutes.to_i
    other = Reservation.joins(:room)
                       .where(user_id: user.id, cancelled: false)
                       .where(datetime_in: date.beginning_of_day..date.end_of_day)
                       .where(rooms: { include_with_day_pass: true })
                       .where.not(id: reservation_id)
                       .sum(:minutes)
    free_remaining = [allotment - other, 0].max
    over = [minutes.to_i - free_remaining, 0].max
    return 0 if over <= 0
    over_rounded = (over / 15.0).ceil * 15
    ((location.overage_rate_in_cents.to_f / 60.0) * over_rounded).round
  end
end
```

- [ ] **Step 4: Run it (passes). Step 5: Commit** `feat(reservations): OveragePreview prospective overage helper`.

---

# Phase 5 — Cancellation

### Task 11: Sibling-booking guard on bundle restore

**Files:**
- Modify: `app/interactors/cancel_reservation.rb` (`restore_redeemed_bundle_passes`, ~lines 60–92)
- Test: `test/interactors/cancel_reservation_coverage_test.rb`

- [ ] **Step 1: Write the failing test** — a member with a bundle books two included rooms the same future day (first burns a pass, second is already-covered). Cancelling the FIRST must NOT restore the pass, because the second booking still needs the day.

```ruby
require "test_helper"

class CancelReservationCoverageTest < ActiveSupport::TestCase
  setup { @operator = operators(:cowork_tahoe); @location = locations(:cowork_tahoe_location) }

  test "cancelling one of two same-day included bookings does not strip the shared pass" do
    ActsAsTenant.with_tenant(@operator) do
      user = create(:user, operator: @operator, original_location: @location, current_location: @location)
      room = create(:room, operator: @operator, location: @location, hourly_rate_in_cents: 0, include_with_day_pass: true)
      dpt  = create(:day_pass_type, operator: @operator, location: @location, included_meeting_room_minutes: 240)
      bundle = DayPassBundle.create!(user: user, operator: @operator, location: @location, day_pass_type: dpt,
                                     quantity_purchased: 5, passes_remaining: 5, purchased_at: Time.current)
      day = (Date.current + 3)
      r1 = create(:reservation, user: user, room: room, minutes: 60, datetime_in: day.to_time + 9.hours)
      Billing::Reservations::RedeemBundlePass.call(reservation: r1, user: user, use_bundle_pass: true)
      assert_equal 4, bundle.reload.passes_remaining
      r2 = create(:reservation, user: user, room: room, minutes: 60, datetime_in: day.to_time + 11.hours)

      CancelReservation.call(reservation: r1, cancelled_by: user)

      assert_equal 4, bundle.reload.passes_remaining, "pass must stay — r2 still needs the day"
    end
  end
end
```

- [ ] **Step 2: Run it (fails — the current restore refunds because it only checks 'wholly future').**

- [ ] **Step 3: Add the sibling guard.** In `restore_redeemed_bundle_passes`, before destroying the minted pass + refunding, skip when another active `include_with_day_pass` reservation on the pass's day (excluding the one being cancelled) still relies on it:

```ruby
      day = redemption.day_pass&.day || reservation.datetime_in.to_date
      sibling = Reservation.joins(:room)
                           .where(user_id: reservation.user_id, cancelled: false)
                           .where(datetime_in: day.beginning_of_day..day.end_of_day)
                           .where(rooms: { include_with_day_pass: true })
                           .where.not(id: reservation.id)
                           .exists?
      next if sibling # another booking still needs this day's coverage
```

(Place this inside the existing loop over the reservation's `kind:"reservation"` redemptions, alongside the current "wholly future" check.)

- [ ] **Step 4: Run it (passes). Step 5: Commit** `fix(reservations): don't restore a bundle pass a sibling booking still needs`.

---

### Task 12: Purchased pass survives cancel and becomes reusable (regression)

**Files:**
- Test: `test/interactors/cancel_reservation_coverage_test.rb` (add)

- [ ] **Step 1: Write the test** — a member books an included room via `buy_day_pass`, cancels it; the purchased pass persists (not refunded), keeps its (now-cancelled) `reservation_id`, and `CoverageState` for a *different* future date returns `:reusable_pass`.

```ruby
  test "a purchased coverage pass survives cancel and becomes reusable" do
    ActsAsTenant.with_tenant(@operator) do
      user = create(:user, operator: @operator, original_location: @location, current_location: @location)
      room = create(:room, operator: @operator, location: @location, hourly_rate_in_cents: 0, include_with_day_pass: true)
      dpt  = create(:day_pass_type, operator: @operator, location: @location, included_meeting_room_minutes: 60, amount_in_cents: 4000)
      res  = create(:reservation, user: user, room: room, minutes: 60, datetime_in: (Date.current + 3).to_time + 9.hours)
      pass = create(:day_pass, user: user, billable: user, operator: @operator, location: @location, day_pass_type: dpt, day: Date.current + 3, reservation: res)

      CancelReservation.call(reservation: res, cancelled_by: user)

      assert DayPass.find_by(id: pass.id), "purchased pass is kept (not refunded)"
      state = Billing::Reservations::CoverageState.for(user: user, room: room, date: Date.current + 6, location: @location)
      assert_equal :reusable_pass, state.outcome
      assert_equal pass.id, state.reusable_pass.id
    end
  end
```

- [ ] **Step 2: Run it.** Expected: PASS (no production change needed — the purchased pass isn't a `kind:"reservation"` redemption, so `restore_redeemed_bundle_passes` leaves it; the cancelled reservation makes it reusable). If it FAILS because cancel destroys/refunds purchased passes, reconcile before continuing.

- [ ] **Step 3: Commit** `test(reservations): purchased coverage pass kept + reusable after cancel`.

---

# Phase 6 — Docs

### Task 13: ADR 0019 + CONTEXT.md

**Files:**
- Create: `docs/adr/0019-included-room-commits-coverage.md`
- Modify: `CONTEXT.md`

- [ ] **Step 1: Write ADR 0019** capturing: an included-room booking requires coverage for its date; confirm-before-booking; block if uncovered (server-enforced, silent auto-buy removed); commit paths reuse→burn→buy; overage independent of coverage source; purchased kept+reusable (via `day_passes.reservation_id`), bundle restored with sibling guard. Reference 0010/0012/0013/0015/0018.

```markdown
# 0019 — Included-room booking commits day-pass coverage

## Status
Accepted (2026-06-30)

## Context
Booking an included room ($0, include_with_day_pass) is a commitment to be in
the space that day, but grants only a ±60-min access window (ADR 0013). Bundle
redemption at booking was opt-in (ADR 0015); when omitted, the API silently
auto-bought a fresh single day pass — even for bundle holders — wasting money.

## Decision
An included-room booking must commit day-pass coverage for its date, decided by
the member before booking:
- Precedence: reuse a leftover purchased pass → burn a bundle pass → buy one.
- Server-enforced (`EnforceCoverage`); the silent auto-buy is deleted. No
  coverage committed ⇒ 422, no reservation.
- Meeting-room overage is charged against the covering pass's included minutes,
  identically for bundle / purchased / existing coverage, and surfaced pre-book.
- On cancel: a bundle pass is restored (future, unused, sibling-guarded); a
  purchased pass is kept and becomes reusable (re-datable) via
  `day_passes.reservation_id`.

## Consequences
- `ChargeAtBooking` remains authoritative for the captured amount; coverage is
  committed before it. Capture-at-booking (ADR 0010) and the location overage
  rate (ADR 0012) are unchanged.
- Paid rooms are untouched.
```

- [ ] **Step 2: Update CONTEXT.md** — in the reservation + day-pass sections, add the coverage-commitment rule, the reusable-pass concept, and that overage is independent of coverage source.

- [ ] **Step 3: Commit** `docs: ADR 0019 + CONTEXT.md — included-room coverage`.

---

# Phase 7 — Mobile

### Task 14: Confirm-copy helper + jest

**Files:**
- Create: `src/utils/coverageConfirm.js`
- Test: `tests/utils/coverage-confirm.test.js`

- [ ] **Step 1: Write the failing test** — `coverageConfirm({state, passesRemaining, dayPassAmountInCents, reusableFromDate, overageInCents})` returns the right `{needsConfirm, title, body, confirmLabel, flag}`:
  - `already_covered`, no overage → `{needsConfirm:false}`.
  - `bundle_available`, N=3, overage 3000 → title/body mention "1 of 3" + "$30.00 overage"; `flag:"use_bundle_pass"`.
  - `needs_purchase`, $40 → body "needs a day pass … $40.00"; `flag:"buy_day_pass"`.
  - `reusable_pass`, from "2026-07-08" → body "existing day pass (from Jul 8)"; `flag:"use_existing_pass"`.

- [ ] **Step 2: Run it (fails).**

- [ ] **Step 3: Write the helper** (pure; formats cents/date):

```javascript
const dollars = (c) => `$${(Number(c || 0) / 100).toFixed(2)}`;
const shortDate = (iso) => new Date(`${iso}T12:00:00`).toLocaleDateString('en-US', { month: 'short', day: 'numeric' });

export function coverageConfirm({ state, dateISO, passesRemaining, dayPassAmountInCents, reusableFromDate, overageInCents } = {}) {
  const over = Number(overageInCents || 0);
  const overLine = over > 0 ? ` Plus a ${dollars(over)} meeting-room overage.` : '';
  const day = dateISO ? shortDate(dateISO) : 'that day';
  switch (state) {
    case 'reusable_pass':
      return { needsConfirm: true, flag: 'use_existing_pass', confirmLabel: 'Use my pass & book',
        title: 'Use your existing day pass?',
        body: `Use your day pass${reusableFromDate ? ` (from ${shortDate(reusableFromDate)})` : ''} for ${day}?${overLine}` };
    case 'bundle_available':
      return { needsConfirm: true, flag: 'use_bundle_pass', confirmLabel: 'Use a pass & book',
        title: 'Use a day pass?',
        body: `This booking uses 1 of your ${passesRemaining} day passes for ${day}.${overLine}` };
    case 'needs_purchase':
      return { needsConfirm: true, flag: 'buy_day_pass', confirmLabel: 'Buy day pass & book',
        title: 'A day pass is required',
        body: `This room needs a day pass for ${day} — ${dollars(dayPassAmountInCents)}.${overLine}` };
    default: // already_covered / not_applicable
      return { needsConfirm: false, flag: null, overLine: overLine.trim() };
  }
}
```

- [ ] **Step 4: Run it (passes). Step 5: Commit** `feat(reserve): coverage confirm-copy helper + tests`.

---

### Task 15: Wire the confirm into the reserve flow

**Files:**
- Modify: the mobile reserve confirmation screen (find it: `grep -rn "use_bundle_pass\|reservations.*create\|Book\b" src/screens` — the reservation-billing redesign screen).
- Modify: `src/api/client.js` — ensure the create-reservation call forwards `use_existing_pass` / `use_bundle_pass` / `buy_day_pass`, and add/point the eligibility call.

- [ ] **Step 1** — After room + date/time are chosen, call the eligibility endpoint; read `coverage`. If `needsConfirm`, show an `Alert`/sheet with the helper's title/body and `[confirmLabel → create with { [flag]: true }] / [Cancel → abort]`. If not, book directly (overage line, if any, in the summary).
- [ ] **Step 2** — On a 422 from create (safety net), surface the server message.
- [ ] **Step 3: Verify in-app** on staging (`__DEV__` build): included room, uncovered future date → each variant (bundle / buy / reusable) books and shows the right copy; paid room unaffected.
- [ ] **Step 4: Commit** `feat(reserve): coverage confirm before booking an included room`.

---

# Phase 8 — Web

### Task 16: Web reserve confirm variants

**Files:**
- Modify: the web reserve confirmation flow (find it: `git grep -ln "use_bundle_pass\|reservations#create\|reserve" app/views app/javascript`).

- [ ] **Step 1** — Mirror Task 15 on web: fetch coverage on room+date selection, render the matching confirm (reuse / bundle / buy) with the overage line, submit the decision flag; block on 422.
- [ ] **Step 2: Verify** on staging (web) each variant + paid-room untouched.
- [ ] **Step 3: Commit** `feat(web): included-room coverage confirm before booking`.

---

## Self-review checklist (run before handoff)

- **Spec coverage:** CoverageState (5 outcomes) → Task 2; reusable link → Task 1; reuse/burn/buy/enforce → Tasks 3–7; controller drop-auto-buy + 422 → Task 8; preview + overage → Tasks 9–10; cancellation sibling-guard + purchased-kept-reusable → Tasks 11–12; docs → Task 13; mobile → Tasks 14–15; web → Task 16. ✓
- **Type/name consistency:** decision flags `use_existing_pass` / `use_bundle_pass` / `buy_day_pass` identical across controller, organizer, interactors, and the mobile helper's `flag`. `CoverageState::Result` fields (`outcome`, `passes_remaining`, `bundle`, `day_pass_type`, `amount_cents`, `reusable_pass`) used consistently. Overage helper `OveragePreview.cents(...)` signature matches its callers. ✓
- **Open verification (not blockers):** the day-pass refund primitive for `BuyCoverageDayPass#rollback` (Task 5 note); the exact Phase-7 eligibility endpoint path (Task 9); the mobile/web reserve screen paths (Tasks 15–16) — implementer greps and adapts.

## Final verification

- [ ] Backend billing suites green **single-process**: `PARALLEL_WORKERS=1 bundle exec rails test test/interactors/billing/ test/services/billing/ test/controllers/api/v1/` + clean boot.
- [ ] Mobile `npx jest` green.
- [ ] Deploy the branch to staging (combined with the existing staging code) and walk each confirm variant before any go-live.
