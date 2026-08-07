# Day Office Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An office-backed day-pass kind whose purchase auto-books a private room for the day from an admin-ordered pool, with bundle support, member reschedule, admin reassign/refund, and a sold-out fallback to a regular day pass.

**Architecture:** A `kind` enum on `DayPassType` (`standard` / `day_office`) plus an ordered `day_pass_type_rooms` pool. Allocation lives inside the `CreateDayPass` organizer family (one authority, every entry point) and mints a $0 office-hold `Reservation` (`reservations.day_office_pass_id` FK) spanning the location's posted hours — which yields Room-Lock access (ADR 0021) and calendar occupancy for free. Room availability alone is capacity: `DayPassType#daily_limit_reached?` grows a day-office branch so all five existing self-serve gates + reschedule + bundle scheduling get office behavior without new call sites. See **ADR 0026** and CONTEXT.md → **Day Office** for the decided semantics.

**Tech Stack:** Rails 8.1 (Minitest, Interactor gem organizers, Pundit, Stimulus/Turbo), Expo/React Native mobile (Jest), Stripe (unchanged — the SKU price is the only money).

---

## Decisions locked with David (2026-08-07 grill session)

| # | Decision |
|---|---|
| 1 | One SKU, pooled rooms, admin priority order; buyer never picks the room |
| 2 | Any room may join a pool (hidden rooms = natural dedicated offices); conflicts with hourly bookings are symmetric — first commitment wins |
| 3 | Hold = $0 comp-style Reservation spanning **posted hours** for the date |
| 4 | Bundle walk-in with no office free: **burn anyway**, door opens, no office, notify member + admins, admin-restorable |
| 5 | Reschedule mirrors existing flows: singles one-tap move (availability-checked); bundle days cancel-then-reschedule |
| 6 | Sold-out purchase: tap → server refusal → fallback sheet offering the regular pass (default room-booking type, else cheapest paid standard) or another day |
| 7 | Room availability is the only capacity gate; `daily_limit` ignored + hidden on office-backed types |
| 8 | Admin power = narrow **Reassign room** on office holds (web + mobile), member notified; refund of the pass invoice cancels hold + rescinds pass in one motion |

**Derived invariants (forced by code, confirmed in ADR 0026):**
- The `%office%` name-match in `CoverageState#suggested_day_pass_type` becomes kind-based; office types stay excluded from coverage suggestions.
- Office holds never draw meeting-room allowances (excluded from all three usage sums).
- Office days are never spent **by implication** when other coverage exists: the door burn keeps ConsumeOnEntry's full guards; explicit in-app redemption/scheduling of a day-office bundle uses reduced guards (only "a pass already exists for that date" blocks).
- A guest redemption never allocates an office (guest shares the holder's room). `included_meeting_room_minutes` defaults to 0 on office types.

## Execution notes (read first)

- **Work in a worktree off `origin/main`** — the repo at `~/Downloads/new-jellyswitch` may sit on a stale branch, and merging to main auto-deploys production. `git fetch origin && git worktree add ../day-office origin/main -b feature/day-office`.
- Copy `.env` into the worktree (`cp ~/Downloads/new-jellyswitch/.env ../day-office/`); backend shells need `eval "$(rbenv init -)"` (Ruby 3.3.10).
- Run tests with `bin/rails test <file>` per task; before the PR run **both suites**: `bin/rails test` AND `bin/rails test:system` (system tests are NOT in the default run; they need OpenSearch on :9200). If Postgres segfaults in parallel, `PARALLEL_WORKERS=1`.
- If two agent sessions run concurrently, use an isolated `DATABASE_URL` (shared `jellyswitch_test` corrupts).
- Commit after every green task. Do not push to `main`.

---

### Task 1: Migrations — kind, room pool, hold FK

**Files:**
- Create: `db/migrate/<ts>_add_kind_to_day_pass_types.rb`
- Create: `db/migrate/<ts>_create_day_pass_type_rooms.rb`
- Create: `db/migrate/<ts>_add_day_office_pass_to_reservations.rb`

- [ ] **Step 1: Write the three migrations** (generate with `bin/rails g migration ...` then fill):

```ruby
class AddKindToDayPassTypes < ActiveRecord::Migration[8.1]
  def change
    add_column :day_pass_types, :kind, :string, null: false, default: "standard"
  end
end
```

```ruby
class CreateDayPassTypeRooms < ActiveRecord::Migration[8.1]
  def change
    create_table :day_pass_type_rooms do |t|
      t.references :day_pass_type, null: false, foreign_key: true
      t.references :room, null: false, foreign_key: true
      t.integer :position, null: false
      t.timestamps
    end
    add_index :day_pass_type_rooms, [:day_pass_type_id, :room_id], unique: true,
              name: "index_dpt_rooms_on_type_and_room"
    add_index :day_pass_type_rooms, [:day_pass_type_id, :position],
              name: "index_dpt_rooms_on_type_and_position"
  end
end
```

```ruby
class AddDayOfficePassToReservations < ActiveRecord::Migration[8.1]
  def change
    # nullify: destroying a pass must never orphan-block a room; the model
    # releases the hold first (DayPass before_destroy), this is the backstop.
    add_reference :reservations, :day_office_pass,
                  foreign_key: { to_table: :day_passes, on_delete: :nullify },
                  index: true
  end
end
```

- [ ] **Step 2: Run and verify** — `bin/rails db:migrate` then `git diff db/schema.rb` shows exactly the three additions. `bin/rails db:rollback STEP=3 && bin/rails db:migrate` round-trips cleanly.
- [ ] **Step 3: Commit** — `git add db/ && git commit -m "feat(day-office): kind column, room pool join table, office-hold FK"`

---

### Task 2: Models — kind enum, pool association, `DayPassTypeRoom`

**Files:**
- Create: `app/models/day_pass_type_room.rb`
- Modify: `app/models/day_pass_type.rb`
- Test: `test/models/day_pass_type_room_test.rb`, additions to `test/models/day_pass_type_test.rb`

- [ ] **Step 1: Write failing tests**

```ruby
# test/models/day_pass_type_room_test.rb
require "test_helper"

class DayPassTypeRoomTest < ActiveSupport::TestCase
  setup do
    @operator = operators(:one)
    @location = locations(:one)
    @type = DayPassType.create!(name: "Day Office", operator: @operator,
                                location: @location, amount_in_cents: 7500, kind: "day_office")
    @room = Room.create!(name: "Office 1", operator: @operator, location: @location)
  end

  test "requires position and unique room per type" do
    DayPassTypeRoom.create!(day_pass_type: @type, room: @room, position: 1)
    dup = DayPassTypeRoom.new(day_pass_type: @type, room: @room, position: 2)
    assert_not dup.valid?
  end

  test "rejects a room from another location" do
    other = Room.create!(name: "Elsewhere", operator: @operator, location: locations(:two))
    row = DayPassTypeRoom.new(day_pass_type: @type, room: other, position: 1)
    assert_not row.valid?
    assert_match(/location/i, row.errors.full_messages.join)
  end
end
```

```ruby
# additions to test/models/day_pass_type_test.rb
  test "kind defaults to standard and day_office requires a location" do
    t = DayPassType.new(name: "X", operator: operators(:one), amount_in_cents: 100)
    assert t.standard?
    t.kind = "day_office"
    assert_not t.valid?
    t.location = locations(:one)
    assert t.valid?
  end

  test "assign_office_rooms! replaces the pool in priority order" do
    type = DayPassType.create!(name: "Day Office", operator: operators(:one),
                               location: locations(:one), kind: "day_office", amount_in_cents: 7500)
    a = Room.create!(name: "A", operator: operators(:one), location: locations(:one))
    b = Room.create!(name: "B", operator: operators(:one), location: locations(:one))
    type.assign_office_rooms!({ b.id => 1, a.id => 2 })
    assert_equal [b.id, a.id], type.office_rooms.map(&:id)
    type.assign_office_rooms!({ a.id => 1 })
    assert_equal [a.id], type.reload.office_rooms.map(&:id)
  end
```

- [ ] **Step 2: Run to verify failure** — `bin/rails test test/models/day_pass_type_room_test.rb test/models/day_pass_type_test.rb` → NameError / NoMethodError.
- [ ] **Step 3: Implement**

```ruby
# app/models/day_pass_type_room.rb
# One row = one room in a Day Office type's pool; position is the admin's
# fill order (1 = first choice). See ADR 0026.
class DayPassTypeRoom < ApplicationRecord
  belongs_to :day_pass_type
  belongs_to :room

  validates :position, numericality: { only_integer: true, greater_than: 0 }
  validates :room_id, uniqueness: { scope: :day_pass_type_id }
  validate :room_matches_type_location

  private

  def room_matches_type_location
    return if room.nil? || day_pass_type.nil?
    return if room.location_id == day_pass_type.location_id
    errors.add(:room, "must belong to the same location as the day pass type")
  end
end
```

In `app/models/day_pass_type.rb`, after `has_many :day_passes`:

```ruby
  has_many :day_pass_type_rooms, -> { order(:position) }, dependent: :destroy
  has_many :office_rooms, through: :day_pass_type_rooms, source: :room

  # String-backed kind: the first *behavioral* distinction between types.
  # Never infer office behavior from the name (retired %office% ILIKE).
  enum :kind, { standard: "standard", day_office: "day_office" }, default: :standard

  validates :location, presence: { message: "is required for Day Office types" }, if: :day_office?

  # Full-list semantics, mirroring Room#reassign_doors!: `positions` is
  # {room_id => position}; rooms absent from the hash leave the pool.
  def assign_office_rooms!(positions)
    transaction do
      day_pass_type_rooms.where.not(room_id: positions.keys).destroy_all
      positions.each do |room_id, position|
        day_pass_type_rooms.find_or_initialize_by(room_id: room_id)
                           .update!(position: position)
      end
    end
  end
```

- [ ] **Step 4: Run tests to green**, fix fixture names if `locations(:two)` etc. differ (check `test/fixtures/`).
- [ ] **Step 5: Commit** — `git commit -am "feat(day-office): kind enum + ordered office-room pool on DayPassType"`

---

### Task 3: `Location#posted_hours_span`

**Files:**
- Modify: `app/models/location.rb` (next to `within_posted_hours?`, ~line 191)
- Test: additions to `test/models/location_test.rb`

- [ ] **Step 1: Failing tests**

```ruby
  test "posted_hours_span returns the local open..close instants for a date" do
    loc = locations(:one)
    loc.update!(time_zone: "America/Los_Angeles", working_day_start: "08:00", working_day_end: "18:00")
    span = loc.posted_hours_span(Date.new(2026, 8, 13))
    assert_equal Time.find_zone!("America/Los_Angeles").local(2026, 8, 13, 8, 0), span.first
    assert_equal Time.find_zone!("America/Los_Angeles").local(2026, 8, 13, 18, 0), span.last
  end

  test "posted_hours_span is nil for blank or overnight windows" do
    loc = locations(:one)
    loc.update!(working_day_start: "", working_day_end: "18:00")
    assert_nil loc.posted_hours_span(Date.current)
    loc.update!(working_day_start: "22:00", working_day_end: "05:00")
    assert_nil loc.posted_hours_span(Date.current)
  end
```

- [ ] **Step 2: Run to verify failure.**
- [ ] **Step 3: Implement** (place directly under `within_posted_hours?`; reuse its parsing idiom):

```ruby
  # The concrete [open, close) instants of `date`'s posted hours in this
  # location's zone — the span a Day Office hold occupies (ADR 0026). Returns
  # nil when the working time is blank/unparseable or the window is overnight
  # or zero-length (a day-office hold needs a same-date daytime span; overnight
  # posted hours are not supported for office holds).
  def posted_hours_span(date)
    zone = ActiveSupport::TimeZone[time_zone.presence || "UTC"] || ActiveSupport::TimeZone["UTC"]
    to_min = ->(hhmm) { (m = hhmm.to_s.match(/\A(\d{1,2}):(\d{2})\z/)) ? m[1].to_i * 60 + m[2].to_i : nil }
    start_min = to_min.call(working_day_start)
    end_min   = to_min.call(working_day_end)
    return nil if start_min.nil? || end_min.nil? || end_min <= start_min

    open_at = zone.local(date.year, date.month, date.day) + start_min.minutes
    [open_at, open_at + (end_min - start_min).minutes]
  end
```

- [ ] **Step 4: Green.** — [ ] **Step 5: Commit** — `git commit -am "feat(day-office): Location#posted_hours_span"`

---

### Task 4: Allocation services — `Allocator`, `ReleaseHold`

**Files:**
- Create: `app/services/day_offices/allocator.rb`, `app/services/day_offices/release_hold.rb`
- Test: `test/services/day_offices/allocator_test.rb`

- [ ] **Step 1: Failing tests** (fixtures: one office type + rooms A/B/C at `locations(:one)` with `working_day_start: "08:00"`, `working_day_end: "18:00"` set in `setup`):

```ruby
require "test_helper"

class DayOffices::AllocatorTest < ActiveSupport::TestCase
  setup do
    @operator = operators(:one)
    @location = locations(:one)
    @location.update!(working_day_start: "08:00", working_day_end: "18:00")
    @type = DayPassType.create!(name: "Day Office", operator: @operator, location: @location,
                                kind: "day_office", amount_in_cents: 7500, included_meeting_room_minutes: 0)
    @a = Room.create!(name: "A", operator: @operator, location: @location, visible: false)
    @b = Room.create!(name: "B", operator: @operator, location: @location)
    @type.assign_office_rooms!({ @a.id => 1, @b.id => 2 })
    @user = users(:member)
    @day = Date.current + 7
  end

  test "picks the first free room by position, hidden rooms included" do
    assert_equal @a, DayOffices::Allocator.available_room(day_pass_type: @type, day: @day)
  end

  test "skips a room with any overlapping reservation that day" do
    span = @location.posted_hours_span(@day)
    Reservation.create!(user: users(:admin), room: @a, datetime_in: span.first + 2.hours, minutes: 60)
    assert_equal @b, DayOffices::Allocator.available_room(day_pass_type: @type, day: @day)
  end

  test "nil when all pool rooms are taken or pool empty / archived" do
    @a.update!(archived: true)
    span = @location.posted_hours_span(@day)
    Reservation.create!(user: users(:admin), room: @b, datetime_in: span.first, minutes: 120)
    assert_nil DayOffices::Allocator.available_room(day_pass_type: @type, day: @day)
  end

  test "allocate! creates a $0 posted-hours hold linked to the pass" do
    pass = DayPass.create!(user: @user, billable: @user, operator: @operator,
                           location: @location, day_pass_type: @type, day: @day, imported: true)
    hold = DayOffices::Allocator.allocate!(day_pass: pass)
    span = @location.posted_hours_span(@day)
    assert_equal @a, hold.room
    assert_equal span.first, hold.datetime_in
    assert_equal ((span.last - span.first) / 60).to_i, hold.minutes
    assert_equal pass.id, hold.day_office_pass_id
    assert_not hold.paid
  end

  test "allocate! returns nil when nothing is free" do
    span = @location.posted_hours_span(@day)
    [@a, @b].each { |r| Reservation.create!(user: users(:admin), room: r, datetime_in: span.first, minutes: 600) }
    pass = DayPass.create!(user: @user, billable: @user, operator: @operator,
                           location: @location, day_pass_type: @type, day: @day, imported: true)
    assert_nil DayOffices::Allocator.allocate!(day_pass: pass)
  end
end
```

- [ ] **Step 2: Run to verify failure.**
- [ ] **Step 3: Implement**

```ruby
# app/services/day_offices/allocator.rb
# Assigns a pool room to a Day Office pass (ADR 0026). Reservations carry no
# DB-level overlap constraint, so allocate! serializes same-type allocation by
# taking FOR UPDATE on the pool's join rows; ReservationValidator remains the
# cross-type backstop (overlap → invalid → nil, caller treats as sold out).
module DayOffices
  class Allocator
    def self.available_room(day_pass_type:, day:, exclude_reservation_id: nil)
      span = day_pass_type.location&.posted_hours_span(day)
      return nil if span.nil?

      day_pass_type.office_rooms.merge(Room.active).detect do |room|
        scope = Reservation.overlapping(span.first, span.last).where(room_id: room.id)
        scope = scope.where.not(id: exclude_reservation_id) if exclude_reservation_id
        !scope.exists?
      end
    end

    # Returns the created hold Reservation, or nil when no room is free.
    def self.allocate!(day_pass:)
      type = day_pass.day_pass_type
      span = type.location&.posted_hours_span(day_pass.day)
      return nil if span.nil?

      Reservation.transaction do
        type.day_pass_type_rooms.lock(true).to_a # serialize same-SKU allocation
        room = available_room(day_pass_type: type, day: day_pass.day)
        next nil if room.nil?

        Reservation.create!(
          user: day_pass.user, room: room,
          datetime_in: span.first, minutes: ((span.last - span.first) / 60).to_i,
          paid: false, attendee_count: 1, day_office_pass: day_pass
        )
      rescue ActiveRecord::RecordInvalid
        nil # lost a cross-type race; caller treats as no office free
      end
    end
  end
end
```

```ruby
# app/services/day_offices/release_hold.rb
# The one way an office hold is released (refund cascade, cancel-scheduled-day,
# pass destroy). Cancelling — not destroying — matches CancelReservation's
# convention and frees the room via Reservation's default_scope.
module DayOffices
  class ReleaseHold
    def self.call(hold)
      return if hold.nil? || hold.cancelled?
      hold.update!(cancelled: true)
    end
  end
end
```

- [ ] **Step 4: Green.** Fixture users (`users(:member)` / `users(:admin)`) — use whatever exists in `test/fixtures/users.yml`.
- [ ] **Step 5: Commit** — `git commit -am "feat(day-office): allocator + release-hold services"`

---

### Task 5: Capacity gate + fallback suggestion + CoverageState kind swap

**Files:**
- Modify: `app/models/day_pass_type.rb` (`daily_limit_reached?`, new `suggested_standard_for`)
- Modify: `app/services/billing/reservations/coverage_state.rb:73-79`
- Test: additions to `test/models/day_pass_type_test.rb`, existing CoverageState test file

- [ ] **Step 1: Failing tests**

```ruby
  test "daily_limit_reached? for day_office types is room availability, ignoring daily_limit" do
    # setup mirrors DayOffices::AllocatorTest: type + rooms A,B; then:
    @type.update!(daily_limit: 99)
    assert_not @type.daily_limit_reached?(day: @day, location: @location)
    span = @location.posted_hours_span(@day)
    [@a, @b].each { |r| Reservation.create!(user: users(:admin), room: r, datetime_in: span.first, minutes: 600) }
    assert @type.daily_limit_reached?(day: @day, location: @location)
  end

  test "suggested_standard_for prefers default_for_room_booking, never day_office" do
    std = DayPassType.create!(name: "Regular", operator: @operator, location: @location,
                              amount_in_cents: 4000, default_for_room_booking: true)
    assert_equal std, DayPassType.suggested_standard_for(@location)
  end
```

- [ ] **Step 2: Verify failure.**
- [ ] **Step 3: Implement.** Replace the body of `daily_limit_reached?` (keep its comment, append to it):

```ruby
  # For day_office types the pool IS the capacity: sold out = no pool room
  # free that day; the stored daily_limit is ignored (decision #7, ADR 0026).
  def daily_limit_reached?(day:, location:)
    if day_office?
      return DayOffices::Allocator.available_room(day_pass_type: self, day: day).nil?
    end
    return false if daily_limit.nil?
    day_passes.where(location: location, day: day).count >= daily_limit
  end

  # The regular pass to offer when an office is sold out — same preference
  # order CoverageState uses for coverage auto-buy suggestions.
  def self.suggested_standard_for(location)
    scope = DayPassType.where(operator_id: location.operator_id)
                       .where("location_id = ? OR location_id IS NULL", location.id)
                       .available.where(visible: true).where("amount_in_cents > 0")
                       .where.not(kind: "day_office")
    scope.where(default_for_room_booking: true).first || scope.order(:amount_in_cents).first
  end
```

In `coverage_state.rb`, replace `suggested_day_pass_type`'s body with a delegation (and delete the `%office%` ILIKE):

```ruby
  # The same SKU the old silent auto-buy chose. Office-backed types are
  # excluded by KIND (was a %office% name-match) — an office pass is never
  # auto-suggested as mere room coverage (ADR 0026).
  def suggested_day_pass_type
    DayPassType.suggested_standard_for(location)
  end
```

- [ ] **Step 4: Green**, including the existing CoverageState tests (`bin/rails test test/services/`). If an existing test seeded a type named "...office..." to assert the ILIKE, update it to `kind: "day_office"`.
- [ ] **Step 5: Commit** — `git commit -am "feat(day-office): availability-based capacity + kind-based coverage exclusion"`

---

### Task 6: Reservation/DayPass linkage + usage-sum exclusions

**Files:**
- Modify: `app/models/reservation.rb`, `app/models/day_pass.rb`
- Modify: `app/models/concerns/permissions.rb` (`day_pass_reservation_charge_info` sum, ~line 396)
- Modify: `app/services/billing/reservations/charge_calculator.rb` (`day_pass_overage_cents` + `subscription_overage_cents` sums)
- Test: `test/models/day_pass_test.rb`, `test/services/billing/reservations/charge_calculator_test.rb` (or wherever its tests live — `grep -r "day_pass_overage" test/`)

- [ ] **Step 1: Failing tests**

```ruby
  # day_pass_test.rb
  test "destroying a pass releases its office hold" do
    # office type + pool from Task 4 setup; then:
    pass = DayPass.create!(user: @user, billable: @user, operator: @operator,
                           location: @location, day_pass_type: @type, day: @day, imported: true)
    hold = DayOffices::Allocator.allocate!(day_pass: pass)
    pass.destroy!
    assert Reservation.unscoped.find(hold.id).cancelled
  end

  # charge calculator test
  test "an office hold does not draw the day-pass meeting allowance" do
    # member holds a day-office pass (allowance 0 would trivially pass; use 60
    # to prove the exclusion): type.update!(included_meeting_room_minutes: 60)
    # allocate! the hold (it spans 600 min on an include_with_day_pass room),
    # then book 30 min on a $0 include_with_day_pass call room the same day:
    # ChargeCalculator must return 0 (30 <= 60 free), i.e. the hold's 600
    # minutes were not counted as usage.
  end
```

(Write the second test concretely against the existing test file's fixture idioms — copy the setup style of the neighboring `day_pass_overage` tests.)

- [ ] **Step 2: Verify failure** (the hold's minutes inflate `other_used` → overage charged → assertion fails).
- [ ] **Step 3: Implement.**

`app/models/reservation.rb` (with the other associations):

```ruby
  belongs_to :day_office_pass, class_name: "DayPass", optional: true

  # A Day Office hold: the $0 reservation minted BY a day-office pass purchase
  # (ADR 0026) — never charged, never drawing meeting-room allowances.
  def day_office_hold?
    day_office_pass_id.present?
  end
```

`app/models/day_pass.rb`:

```ruby
  # Live office hold only (Reservation default_scope hides cancelled).
  has_one :office_hold, class_name: "Reservation", foreign_key: :day_office_pass_id

  # Single release authority for every destroy path (refund rescind,
  # cancel-scheduled-day, console) — see ADR 0026.
  before_destroy { DayOffices::ReleaseHold.call(office_hold) }

  delegate :day_office?, to: :day_pass_type, allow_nil: true
```

Add `.where(day_office_pass_id: nil)` to all three usage sums:
- `permissions.rb` `day_pass_reservation_charge_info` — the `used_minutes = Reservation.joins(:room)...` chain
- `charge_calculator.rb` `day_pass_overage_cents` — the `other_used = Reservation.joins(:room)...` chain
- `charge_calculator.rb` `subscription_overage_cents` — the `other_used = Reservation.where(...)` chain (a member's office hold must not eat their plan Hour Pool)

- [ ] **Step 4: Green** — run the whole `test/services` + `test/models` set; the exclusion must not break existing overage tests.
- [ ] **Step 5: Commit** — `git commit -am "feat(day-office): hold linkage, destroy-releases-hold, allowance-sum exclusions"`

---

### Task 7: `AllocateDayOffice` interactor in every purchase organizer

**Files:**
- Create: `app/interactors/billing/day_passes/allocate_day_office.rb`
- Modify: `app/interactors/billing/day_passes/create_day_pass.rb`, `update_payment_and_create_day_pass.rb`, `create_free_day_pass.rb`, `create_day_pass_and_checkin.rb`, `update_payment_and_create_day_pass_and_checkin.rb`
- Test: `test/interactors/billing/day_passes/allocate_day_office_test.rb`

- [ ] **Step 1: Failing tests**

```ruby
require "test_helper"

class Billing::DayPasses::AllocateDayOfficeTest < ActiveSupport::TestCase
  # setup: office type + 1-room pool as in Task 4; a member with Stripe
  # customer (copy the setup idiom from the existing CreateDayPass tests —
  # `grep -r "CreateDayPass" test/` — StripeMock or the suite's stub pattern).

  test "purchase creates pass + hold atomically" do
    result = Billing::DayPasses::CreateDayPass.call(
      user_id: @user.id, operator: @operator, location: @location,
      params: { day_pass_type: @type.id.to_s, day: @day, operator_id: @operator.id })
    assert result.success?
    assert_equal "A", result.day_pass.office_hold.room.name
  end

  test "sold out fails the organizer BEFORE any charge, with structured context" do
    span = @location.posted_hours_span(@day)
    Reservation.create!(user: users(:admin), room: @a, datetime_in: span.first, minutes: 600)
    result = Billing::DayPasses::CreateDayPass.call(
      user_id: @user.id, operator: @operator, location: @location,
      params: { day_pass_type: @type.id.to_s, day: @day, operator_id: @operator.id })
    assert_not result.success?
    assert_equal :day_office_sold_out, result.error_code
    assert_equal 0, DayPass.where(day_pass_type: @type).count
    assert_equal 0, Invoice.count # nothing charged
  end

  test "charge failure rolls the hold back" do
    # force ChargeDayPassInvoice to fail (declined-card stub per the suite's
    # existing pattern); assert DayPass.count == 0 and no non-cancelled
    # reservation remains on @a for @day.
  end

  test "no-op for standard types" do
    result = Billing::DayPasses::AllocateDayOffice.call(day_pass: day_passes(:one))
    assert result.success?
  end
end
```

- [ ] **Step 2: Verify failure.**
- [ ] **Step 3: Implement**

```ruby
# app/interactors/billing/day_passes/allocate_day_office.rb
# Runs right after SaveDayPass in every purchase organizer: allocation must
# succeed BEFORE money moves, and its rollback rides the organizer's unwind.
class Billing::DayPasses::AllocateDayOffice
  include Interactor

  delegate :day_pass, to: :context

  def call
    return unless day_pass&.day_office?

    hold = DayOffices::Allocator.allocate!(day_pass: day_pass)
    if hold.nil?
      context.error_code = :day_office_sold_out
      context.fallback_day_pass_type = DayPassType.suggested_standard_for(day_pass.location)
      context.fail!(message: "#{day_pass.day_pass_type.name.pluralize} are fully booked for " \
                             "#{day_pass.day.strftime('%B %e')}. Try another day.")
    end
    context.office_hold = hold
  end

  def rollback
    DayOffices::ReleaseHold.call(context.office_hold)
  end
end
```

Insert `Billing::DayPasses::AllocateDayOffice` immediately after `Billing::DayPasses::SaveDayPass` in **all five** organizers (in `CreateFreeDayPass` it goes after `SaveDayPass`, which follows `FindFreeDayPass`).

- [ ] **Step 4: Green** — also run the full existing `test/interactors/billing/day_passes/` set (standard-type behavior must be untouched).
- [ ] **Step 5: Commit** — `git commit -am "feat(day-office): allocation step in all day-pass purchase organizers"`

---

### Task 8: API — sold-out payload, serializer fields, confirmation note

**Files:**
- Modify: `app/controllers/api/v1/day_passes_controller.rb` (`#types`, `#index`, `#create`, `sold_out_message` area)
- Test: `test/controllers/api/v1/day_passes_controller_test.rb` (follow the file's existing auth/setup idiom)

- [ ] **Step 1: Failing request tests**

```ruby
  test "types payload carries kind" do
    get "/api/v1/day_pass_types", headers: auth_headers(@member)
    assert_equal "day_office", JSON.parse(response.body).find { |t| t["id"] == @type.id }["kind"]
  end

  test "sold-out purchase returns structured fallback" do
    fill_all_pool_rooms!(@day) # helper: reservation on every pool room
    post "/api/v1/day_passes", params: { day_pass_type_id: @type.id, date: @day.iso8601 },
         headers: auth_headers(@member)
    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_equal "day_office_sold_out", body["code"]
    assert_equal @std.id, body.dig("fallback_day_pass_type", "id")
  end

  test "purchase response and index carry the office room" do
    post "/api/v1/day_passes", params: { day_pass_type_id: @type.id, date: @day.iso8601 },
         headers: auth_headers(@member)
    assert_match(/Office A/, JSON.parse(response.body)["confirmation_note"])
    get "/api/v1/day_passes", headers: auth_headers(@member)
    row = JSON.parse(response.body).find { |p| p["day"] == @day.iso8601 }
    assert_equal "A", row["office_room"]
  end
```

(Adapt param names to the controller's actual `#create` params — it reads `params[:date]` and the type via the existing lookup; check the top of `#create` above line 95 for the type-id param name before writing.)

- [ ] **Step 2: Verify failure.**
- [ ] **Step 3: Implement.**

`#types` map — add `kind: t.kind`.

`#index` map — add:

```ruby
        office_room: dp.office_hold&.room&.name,
        office_window: dp.office_hold&.window_label,
```

`#create`: (a) the pre-check `render_error(sold_out_message(...))` for a `day_office?` type becomes `render_day_office_sold_out(day_pass_type, date)`; (b) after the interactor call, on failure with `result.error_code == :day_office_sold_out` render the same payload (race backstop); (c) on success include the note. Add privates:

```ruby
  def render_day_office_sold_out(day_pass_type, day)
    fallback = DayPassType.suggested_standard_for(current_location)
    render json: {
      error: sold_out_message(day_pass_type, day),
      code: "day_office_sold_out",
      fallback_day_pass_type: fallback && {
        id: fallback.id, name: fallback.name, price: fallback.amount_in_cents,
      },
    }, status: :unprocessable_entity
  end

  def office_confirmation_note(day_pass)
    hold = day_pass&.office_hold
    return nil unless hold
    "#{hold.room.name} is yours #{hold.window_label}."
  end
```

and merge `confirmation_note: office_confirmation_note(result.day_pass)` into the success JSON (nil for standard types — the mobile client renders it only when present).

- [ ] **Step 4: Green** (`bin/rails test test/controllers/api/v1/day_passes_controller_test.rb`).
- [ ] **Step 5: Commit** — `git commit -am "feat(day-office): sold-out fallback payload + office fields in API"`

---

### Task 9: Reschedule moves the hold

**Files:**
- Create: `app/services/day_offices/move_hold.rb`
- Modify: `app/controllers/api/v1/day_passes_controller.rb#reschedule` (the `day_pass.update!(day: new_day)` line)
- Test: additions to the same controller test file

- [ ] **Step 1: Failing tests**

```ruby
  test "rescheduling a day-office pass moves its hold" do
    pass = buy_office_pass!(@day) # helper using the purchase endpoint
    patch "/api/v1/day_passes/#{pass_id}/reschedule", params: { day: (@day + 1).iso8601 },
          headers: auth_headers(@member)
    assert_response :success
    hold = DayPass.find(pass_id).office_hold
    assert_equal (@day + 1), hold.datetime_in.to_date
    assert_equal 1, Reservation.unscoped.where(day_office_pass_id: pass_id, cancelled: true).count
  end

  test "reschedule refuses when the target date has no office" do
    pass = buy_office_pass!(@day)
    fill_all_pool_rooms!(@day + 1)
    patch "/api/v1/day_passes/#{pass_id}/reschedule", params: { day: (@day + 1).iso8601 },
          headers: auth_headers(@member)
    assert_response :unprocessable_entity
    assert_equal @day, DayPass.find(pass_id).day # unchanged
  end
```

- [ ] **Step 2: Verify failure.**
- [ ] **Step 3: Implement**

```ruby
# app/services/day_offices/move_hold.rb
# Atomic date-move: allocate on the target date first, then release the old
# hold and move the pass — so a full target date changes nothing.
module DayOffices
  class MoveHold
    Result = Struct.new(:ok?, :hold)

    def self.call(day_pass:, new_day:)
      DayPass.transaction do
        old_hold = day_pass.office_hold
        day_pass.update!(day: new_day)
        new_hold = Allocator.allocate!(day_pass: day_pass)
        raise ActiveRecord::Rollback if new_hold.nil?
        ReleaseHold.call(old_hold)
        return Result.new(true, new_hold)
      end
      Result.new(false, nil)
    end
  end
end
```

In `#reschedule`, replace the plain update for office passes (the existing `daily_limit_reached?` target-day pre-check already speaks day-office thanks to Task 5):

```ruby
    old_day = day_pass.day
    if day_pass.day_office?
      move = DayOffices::MoveHold.call(day_pass: day_pass, new_day: new_day)
      return render_day_office_sold_out(day_pass.day_pass_type, new_day) unless move.ok?
    else
      day_pass.update!(day: new_day)
    end
```

(keep the existing mailer + render lines after it unchanged).

- [ ] **Step 4: Green.** — [ ] **Step 5: Commit** — `git commit -am "feat(day-office): reschedule moves the office hold atomically"`

---

### Task 10: Bundles — `ScheduleDay` office branch + `redeem_today` routing

**Files:**
- Modify: `app/interactors/billing/day_pass_bundles/schedule_day.rb`
- Modify: `app/controllers/api/v1/day_passes_controller.rb#redeem_today`
- Test: `test/interactors/billing/day_pass_bundles/schedule_day_test.rb` additions; controller test additions

**Semantics (from the grill + ADR 0026):** for a day-office bundle, "covered for access" must not suppress the mint — the office is the point. Reduced guard: only an existing same-date pass blocks. Member self-serve scheduling is strict (no office → `:sold_out`, nothing burned); the staff path (no `enforce_daily_limit`) is best-effort (schedules + no office, staff judgment). Cancel-scheduled-day needs no change — `DayPass#before_destroy` releases the hold (Task 6).

- [ ] **Step 1: Failing tests**

```ruby
  test "scheduling a day-office bundle day allocates a room" do
    result = Billing::DayPassBundles::ScheduleDay.call(
      user: @user, location: @location, date: @day, performed_by: @user, enforce_daily_limit: true)
    assert_equal :scheduled, result.outcome
    assert_equal "A", result.day_pass.office_hold.room.name
  end

  test "a member with an active subscription can still schedule an office day" do
    give_active_subscription!(@user)
    result = Billing::DayPassBundles::ScheduleDay.call(
      user: @user, location: @location, date: @day, performed_by: @user, enforce_daily_limit: true)
    assert_equal :scheduled, result.outcome
  end

  test "member scheduling with no office free is sold_out and burns nothing" do
    fill_all_pool_rooms!(@day)
    before = @bundle.reload.passes_remaining
    result = Billing::DayPassBundles::ScheduleDay.call(
      user: @user, location: @location, date: @day, performed_by: @user, enforce_daily_limit: true)
    assert_equal :sold_out, result.outcome
    assert_equal before, @bundle.reload.passes_remaining
  end

  test "staff scheduling with no office free proceeds without one" do
    fill_all_pool_rooms!(@day)
    result = Billing::DayPassBundles::ScheduleDay.call(
      user: @user, location: @location, date: @day, performed_by: users(:admin))
    assert_equal :scheduled, result.outcome
    assert_nil result.day_pass.office_hold
  end

  test "cancelling a scheduled office day releases the hold and restores the pass" do
    result = Billing::DayPassBundles::ScheduleDay.call(
      user: @user, location: @location, date: @day, performed_by: @user, enforce_daily_limit: true)
    hold_id = result.day_pass.office_hold.id
    Billing::DayPassBundles::CancelScheduledDay.call(day_pass: result.day_pass, performed_by: @user)
    assert Reservation.unscoped.find(hold_id).cancelled
  end
```

(`@bundle` setup: a `DayPassBundle` on a `kind: "day_office"`, `quantity: 5` type — copy the bundle-creation idiom from the existing `schedule_day_test.rb`.)

- [ ] **Step 2: Verify failure** (test 2 fails on `:already_covered`, test 1 on missing hold).
- [ ] **Step 3: Implement in `schedule_day.rb`.**

In `#call`, change the covered guard to respect the kind — replace `if already_covered?(date, tz)` with:

```ruby
    office_bundle = eligible_bundle(date, tz)&.day_pass_type&.day_office?
    if already_covered?(date, tz, office: office_bundle)
      context.outcome = :already_covered
      return
    end
```

and adjust the private method:

```ruby
  # Mirrors ConsumeOnEntry's guards, scoped to the target date. For a
  # day-office bundle the office is the point, not the access — subscription/
  # lease/reservation coverage must not suppress the mint; only an existing
  # same-date pass does (ADR 0026).
  def already_covered?(date, tz, office: false)
    unless office
      return true if user.has_active_subscription?
      return true if user.has_active_lease?(location)
      day_start = date.in_time_zone(tz).beginning_of_day
      day_end   = date.in_time_zone(tz).end_of_day
      return true if user.reservations.where(cancelled: false)
                         .where(datetime_in: day_start..day_end).exists?
    end
    user.day_passes.for_location(location).for_day(date).exists?
  end
```

(Note: `eligible_bundle` is currently called after this guard — hoist the call as shown and reuse the variable below so it isn't computed twice.)

Inside the `bundle.with_lock do ... end` block, after `DayPass.create!` and **before** `burn_locked!`:

```ruby
      if bundle.day_pass_type.day_office?
        hold = DayOffices::Allocator.allocate!(day_pass: day_pass)
        if hold.nil? && context.enforce_daily_limit
          # Member self-serve is strict: no office, no burn (the Task 5 gate
          # normally catches this; here we lost a race).
          day_pass.destroy!
          context.day_pass_type = bundle.day_pass_type
          context.outcome = :sold_out
          next
        end
      end
```

`#redeem_today`: locate the active-bundle lookup at the top of the action; when that bundle's type is `day_office?`, call `ScheduleDay` for today instead of `ConsumeOnEntry`, mapping outcomes to the action's existing responses (`:scheduled` → the success render; `:sold_out` → `render_day_office_sold_out(result.day_pass_type, Date.current)`; other outcomes → the action's existing error strings). Door burns keep full guards — that stays in Task 11.

- [ ] **Step 4: Green**, plus the full existing bundle interactor tests.
- [ ] **Step 5: Commit** — `git commit -am "feat(day-office): bundle scheduling allocates; reduced covered-guards for office bundles"`

---

### Task 11: Walk-in door burn — best-effort allocation + notifications

**Files:**
- Modify: `app/interactors/billing/day_pass_bundles/consume_on_entry.rb` (inside the `bundle.with_lock` block, after `burn_locked!`)
- Test: `test/interactors/billing/day_pass_bundles/consume_on_entry_test.rb` additions

- [ ] **Step 1: Failing tests**

```ruby
  test "door burn on a day-office bundle allocates a room" do
    result = Billing::DayPassBundles::ConsumeOnEntry.call(user: @user, location: @location)
    assert_equal :redeemed, result.outcome
    assert_equal "A", @user.day_passes.for_day(Date.current).first.office_hold.room.name
  end

  test "door burn with no office free still burns, opens, and notifies" do
    fill_all_pool_rooms!(Date.current)
    result = Billing::DayPassBundles::ConsumeOnEntry.call(user: @user, location: @location)
    assert_equal :redeemed, result.outcome # decision #4: never lock out prepaid
    assert_nil @user.day_passes.for_day(Date.current).first.office_hold
    # assert one member push + one admin notification enqueued — use the
    # suite's existing assert_enqueued_with idiom from the neighboring tests
  end
```

- [ ] **Step 2: Verify failure.**
- [ ] **Step 3: Implement.** After `bundle.burn_locked!(...)` (still inside the lock block, before `context.outcome = :redeemed`):

```ruby
      if bundle.day_pass_type.day_office?
        hold = DayOffices::Allocator.allocate!(day_pass: day_pass)
        DayOffices::Notify.walk_in(day_pass: day_pass, hold: hold)
      end
```

Create `app/services/day_offices/notify.rb` with two class methods:

- `walk_in(day_pass:, hold:)` — hold present → member push "🔑 {room} is yours today ({window})"; hold nil → member push "No offices are left today — see staff, your pass still works" **and** an admin notification ("{member} arrived on a Day Office pass but no office was free — reassign or restore"). Model the member push on the `ReservationCharged` push in `app/interactors/billing/reservations/charge_at_booking.rb:172-187`, and the admin side on `app/interactors/send_admin_notification_for_paid_room.rb`. Remote-push payload data goes **under the `body` key** (established gotcha).
- `reassigned(hold:, old_room:)` — used by Task 12: member push + `UserMailer` email "Your office for {date} is now {room}".

Add a `UserMailer#day_office_reassigned(reservation_id, old_room_name)` with a minimal text/HTML pair matching the mailer's house style (copy the structure of `day_pass_rescheduled`).

- [ ] **Step 4: Green.** — [ ] **Step 5: Commit** — `git commit -am "feat(day-office): walk-in burn allocates best-effort + notifies (decision #4)"`

---

### Task 12: Admin reassign — endpoints + service

**Files:**
- Create: `app/services/day_offices/reassign_room.rb`
- Modify: `config/routes.rb` (admin API reservations block ~line 258; operator reservations resources ~line 840)
- Modify: `app/controllers/api/v1/admin/reservations_controller.rb`, `app/controllers/operator/reservations_controller.rb`
- Test: request tests in both controllers' test files

- [ ] **Step 1: Failing tests**

```ruby
  # api/v1/admin/reservations_controller_test.rb
  test "admin reassigns an office hold to a free room and member is notified" do
    patch "/api/v1/admin/reservations/#{@hold.id}/reassign_room",
          params: { room_id: @c.id }, headers: auth_headers(@admin)
    assert_response :success
    assert_equal @c.id, @hold.reload.room_id
  end

  test "reassign refuses an occupied room, a non-hold reservation, and a non-admin" do
    # occupied → 422; @plain_reservation → 422 "not an office hold"; member auth → 403
  end

  test "reassign_options lists free rooms for the hold's window" do
    get "/api/v1/admin/reservations/#{@hold.id}/reassign_options", headers: auth_headers(@admin)
    ids = JSON.parse(response.body).map { |r| r["id"] }
    assert_includes ids, @c.id
    assert_not_includes ids, @hold.room_id
  end
```

- [ ] **Step 2: Verify failure (404s — routes missing).**
- [ ] **Step 3: Implement.**

```ruby
# app/services/day_offices/reassign_room.rb
# Admin-only narrow move (decision #8): any room of the location, hidden
# included, that is free for the hold's exact window. Notifies the member.
module DayOffices
  class ReassignRoom
    Result = Struct.new(:ok?, :error)

    def self.call(hold:, room:)
      return Result.new(false, "Not a Day Office hold.") unless hold&.day_office_hold?
      return Result.new(false, "Room not found at this location.") if room.nil? ||
        room.location_id != hold.room.location_id || room.archived?

      old_room = hold.room
      return Result.new(true, nil) if room.id == old_room.id

      taken = Reservation.overlapping(hold.datetime_in, hold.datetime_out)
                         .where(room_id: room.id).where.not(id: hold.id).exists?
      return Result.new(false, "#{room.name} is already booked then.") if taken

      hold.update!(room: room)
      DayOffices::Notify.reassigned(hold: hold, old_room: old_room)
      Result.new(true, nil)
    end
  end
end
```

Routes — admin API (inside the existing admin `resources :reservations` member block):

```ruby
        patch :reassign_room
        get :reassign_options
```

and on the operator side add `patch :reassign_room, on: :member` to the `resources :reservations` declaration.

Admin API controller actions (auth follows the file's existing admin gate):

```ruby
  def reassign_room
    hold = Reservation.find(params[:id])
    room = Room.active.find_by(id: params[:room_id])
    result = DayOffices::ReassignRoom.call(hold: hold, room: room)
    return render_error(result.error) unless result.ok?
    render json: { success: true, room: hold.reload.room.name }
  end

  def reassign_options
    hold = Reservation.find(params[:id])
    return render_error("Not a Day Office hold.") unless hold.day_office_hold?
    rooms = Room.active.where(location_id: hold.room.location_id).where.not(id: hold.room_id)
                .order(:name).reject do |r|
      Reservation.overlapping(hold.datetime_in, hold.datetime_out)
                 .where(room_id: r.id).where.not(id: hold.id).exists?
    end
    render json: rooms.map { |r| { id: r.id, name: r.name, hidden: !r.visible } }
  end
```

Operator web `reassign_room` mirrors it (staff-gated like the file's other admin actions, flash + `turbo_redirect` back). **Cancel-hold and refund need no new endpoints:** the existing reservation destroy paths flip `cancelled` (freeing the room, pass keeps building access), and refunding the pass's invoice cascades through `RescindForInvoice` → `before_destroy` → hold released (Task 6). Verify `RescindForInvoice`'s live-reservation guard doesn't block it: the guard reads `day_pass.reservation` (the **coverage** link `day_passes.reservation_id`), not `office_hold` — add one regression test in `test/interactors/billing/day_passes/rescind_for_invoice_test.rb` asserting a refunded office pass is destroyed and its hold cancelled.

- [ ] **Step 4: Green.** — [ ] **Step 5: Commit** — `git commit -am "feat(day-office): admin reassign-room endpoints + refund cascade regression test"`

---

### Task 13: Web admin — type form (kind, pool, hidden fields)

**Files:**
- Modify: `app/views/operator/day_pass_types/_form.html.erb` and `_edit_form.html.erb`
- Modify: `app/helpers/day_pass_types_helper.rb` (create/update param allowlists + a new `assign_office_rooms_from_params` helper)
- Modify: `app/controllers/operator/day_pass_types_controller.rb` (#create/#update call the assign helper)
- Create: `app/javascript/controllers/day_pass_type_form_controller.js`
- Test: `test/controllers/operator/day_pass_types_controller_test.rb` additions

- [ ] **Step 1: Failing test**

```ruby
  test "creating a day-office type with an ordered pool" do
    post operator_day_pass_types_path, params: { day_pass_type: {
      name: "Day Office", amount_in_cents: 7500, kind: "day_office",
      location_id: @location.id, included_meeting_room_minutes: 0,
    }, office_room_positions: { @a.id.to_s => "1", @b.id.to_s => "2" } }
    type = DayPassType.find_by(name: "Day Office")
    assert_equal "day_office", type.kind
    assert_equal [@a.id, @b.id], type.office_rooms.map(&:id)
  end
```

- [ ] **Step 2: Verify failure.**
- [ ] **Step 3: Implement.**
  - Both forms: a `kind` select (`Standard` / `Day Office`) wrapped in `data-controller="day-pass-type-form"`; a "Day Office rooms" section listing every `current_location` room (name + hidden badge) with a numeric `office_room_positions[<room_id>]` input ("1 = first choice; blank = not in pool"); helper text under the allowance field: "Day Office default is 0 — the office is included; extra room time bills at the location overage rate."
  - Stimulus controller: on kind change, toggle `hidden` on the `daily_limit` wrapper (office types: availability is the gate) and the pool section (standard types); on switch **to** day_office, if the allowance input is blank set it to `0`. Targets: `kind`, `dailyLimit`, `pool`, `allowance`. Keep it ~30 lines, no external deps.
  - Helper allowlists: permit `:kind` (create + update). In the controller, after successful save: `@day_pass_type.assign_office_rooms!(office_room_positions_params)` where the helper method reads `params[:office_room_positions].to_h { |id, pos| [id.to_i, pos.to_i] }.select { |_, p| p.positive? }` (guard `if @day_pass_type.day_office?`).
- [ ] **Step 4: Green.** — [ ] **Step 5: Commit** — `git commit -am "feat(day-office): operator type form — kind select + ordered room pool"`

---

### Task 14: Web — profile reassign button + purchase-flash suggestion

**Files:**
- Modify: the admin user-profile day-pass list partial — find it with `rg -l "day_pass" app/views/operator/users/ app/views/operator/day_passes/`; the row rendering each pass gains, when `day_pass.office_hold` present and viewer is staff: the office name + a "Reassign" link to a small form posting `reassign_room` (room select from `Room.active.where(location_id:)`)
- Modify: `app/controllers/operator/day_passes_controller.rb:89-93` — the sold-out flash gains the suggestion: `flash[:error] = "#{sold_out_message}. A #{suggested.name} is available instead."` when `DayPassType.suggested_standard_for(current_location)` returns one
- Test: one request test per change, following each file's existing idioms

- [ ] **Steps: test-fail-implement-green-commit** as in prior tasks. Commit — `git commit -am "feat(day-office): web reassign surface + sold-out suggestion copy"`

---

### Task 15: Mobile — fallback sheet, confirmation note, office chips

**Repo:** `~/Downloads/jellyswitch-mobile` (branch off main). Jest runs via `./node_modules/.bin/jest`.

**Files:**
- Modify: `src/screens/account/DayPassScreen.js`
- Create: `src/utils/dayOffice.js` + `tests/utils/day-office.test.js`

- [ ] **Step 1: Failing Jest test**

```js
// tests/utils/day-office.test.js
import { dayOfficeSoldOut, officeLine } from '../../src/utils/dayOffice';

test('detects the structured sold-out error', () => {
  const err = { response: { data: { code: 'day_office_sold_out', error: 'Day Offices are fully booked…',
    fallback_day_pass_type: { id: 9, name: 'Regular Day Pass', price: 4000 } } } };
  expect(dayOfficeSoldOut(err).fallback.name).toBe('Regular Day Pass');
  expect(dayOfficeSoldOut({ response: { data: { error: 'nope' } } })).toBeNull();
});

test('officeLine renders pass office fields', () => {
  expect(officeLine({ office_room: 'Office A', office_window: '8:00 AM – 6:00 PM' }))
    .toBe('Office A · 8:00 AM – 6:00 PM');
  expect(officeLine({})).toBeNull();
});
```

- [ ] **Step 2: `./node_modules/.bin/jest tests/utils/day-office.test.js` → fails.**
- [ ] **Step 3: Implement**

```js
// src/utils/dayOffice.js
export function dayOfficeSoldOut(err) {
  const d = err?.response?.data;
  if (d?.code !== 'day_office_sold_out') return null;
  return { message: d.error, fallback: d.fallback_day_pass_type || null };
}

export function officeLine(pass) {
  if (!pass?.office_room) return null;
  return pass.office_window ? `${pass.office_room} · ${pass.office_window}` : pass.office_room;
}
```

- [ ] **Step 4: Wire into `DayPassScreen.js`:**
  - In `handleBuyPaid`'s catch (`:215` region) and the free-pass catch: `const so = dayOfficeSoldOut(e); if (so) { Alert.alert('No offices left', so.fallback ? `${so.message}\n\nGet a ${so.fallback.name} for ${formatPrice(so.fallback.price)} instead?` : so.message, so.fallback ? [{ text: 'Pick another day', style: 'cancel' }, { text: `Buy ${so.fallback.name}`, onPress: () => buyFallback(so.fallback) }] : [{ text: 'OK' }]); return; }` — `buyFallback` reuses the existing purchase call with the fallback type object and the already-selected date (mirror `handleBuyPaid`'s body; the two-option Alert idiom is already at `:221-236`).
  - Purchase success alerts (`:210`, `:258`, `:302`): capture `const res = await dayPassesAPI.create(data);` and append `res?.data?.confirmation_note` to the alert body when present (server-driven line — no client copy).
  - Pass rows: in the MY DAY PASSES renderer (`:693-731`) and SCHEDULED DAYS renderer (`:798-820`), under the date line render `officeLine(pass)` in the muted style used by neighboring metadata rows.
  - Use `price` fields consistently with the screen's existing reads (it reads `price`; the fallback payload sends `price` in cents — format with the screen's existing helper).
- [ ] **Step 5: Full Jest suite green (`./node_modules/.bin/jest`), commit** — `git commit -am "feat(day-office): sold-out fallback sheet, office confirmation + chips"`

---

### Task 16: Mobile admin — reassign UI

**Files:**
- Modify: `src/screens/admin/MemberDetailScreen.js`, `src/api/client.js`

- [ ] **Step 1: `src/api/client.js`** — next to `adminReservationsAPI` add:

```js
  reassignOptions: (id) => api.get(`/admin/reservations/${id}/reassign_options`),
  reassignRoom: (id, roomId) => api.patch(`/admin/reservations/${id}/reassign_room`, { room_id: roomId }),
```

- [ ] **Step 2: `MemberDetailScreen.js`** — the member's day-pass/scheduled-day rows already render from the admin payload; where a row carries `office_room` (add the same two fields to whatever admin endpoint feeds this list — check `scheduled_bundle_days` at `api/v1/admin/members_controller.rb` and add `office_room`/`hold_id` there in the same style as Task 8's `#index` additions), render a "Reassign office" link opening a simple options sheet: fetch `reassignOptions(hold_id)`, `Alert.alert` with up to ~4 room choices (or a modal list matching the screen's existing pickers at `:1520-1560`), then `reassignRoom(hold_id, roomId)` and refresh. Follow the screen's existing fetch/refresh idioms (`:154-169`).
- [ ] **Step 3: Manual verification** — run the app against staging (`tahoelonghouse.jellyswitch.net` test tenant), grant an office pass, reassign it, confirm the member-side push arrives. Commit — `git commit -am "feat(day-office): admin mobile reassign UI"`

---

### Task 17: Ship

- [ ] **Backend PR** off `feature/day-office` → both suites green (`bin/rails test` + `bin/rails test:system`; watch the run to completion — `gh run watch` can swallow exit codes, check conclusions explicitly). Merge = prod deploy (v-next).
- [ ] **Backfill none needed** — no data migration. The API is additive; pre-OTA mobile clients can buy office types safely (server allocates; they just miss the office line and fallback sheet).
- [ ] **Operator step (David, post-deploy):** edit Cowork Tahoe's existing "Day Office" type → kind = Day Office, pool = the two office rooms in priority order, allowance 0. `daily_limit` is ignored from then on.
- [ ] **Mobile OTA ×4** from a clean `main` checkout: `BRAND=<brand> eas update --branch production` for all four brands.
- [ ] **Live smoke:** buy a Day Office on prod for tomorrow (refund after): pass + hold created, room shows busy on the admin calendar, reschedule moves it, refund rescinds pass + frees room.

## Deferred / follow-ups (explicitly out of V1)

- **Concierge flip:** the scripted need-flow still routes "private office for a day" to staff capture; pointing it at self-serve checkout (and updating CONTEXT.md's Concierge mapping) is its own small PR.
- **Proactive per-date greying** of sold-out office cards in the type list (decision #6 chose reactive-only).
- **Staff sold-out override** on admin grant paths (admins currently get the same refusal; freeing a room first is the workaround).
- **Multi-bundle draw order** ignores kind (existing single-active-bundle assumption unchanged).
- Room-usage/utilization reporting treats holds as ordinary reservations; a `day_office_hold?` filter for reports is trivial later if wanted.

## Self-review notes

- Every grill decision (#1–#8) maps to a task: #1/#2 → Tasks 1–2, #3 → Tasks 3–4, #4 → Task 11, #5 → Tasks 9–10, #6 → Tasks 8+15, #7 → Task 5, #8 → Tasks 12/14/16.
- Names used consistently: `DayOffices::Allocator.{available_room,allocate!}`, `ReleaseHold.call`, `MoveHold.call`, `ReassignRoom.call`, `Notify.{walk_in,reassigned}`, `DayPassType#assign_office_rooms!`, `#day_office?`, `.suggested_standard_for`, `Reservation#day_office_hold?`, `DayPass#office_hold`, payload keys `code/fallback_day_pass_type/confirmation_note/office_room/office_window`.
- Known small risks called out in-task: fixture names (Tasks 2/4), the type-id param name in `#create` (Task 8), the profile partial location (Task 14), the admin scheduled-days payload (Task 16).
