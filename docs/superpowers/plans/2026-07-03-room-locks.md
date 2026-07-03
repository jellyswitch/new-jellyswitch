# Room Locks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Doors attached to a Room become reservation-gated Room Locks (ADR 0021): holder-during-booking + staff only, surfaced on the booking card instead of the Keys list, with Room Entries kept out of door-punch semantics.

**Architecture:** `doors.room_id` is the classification (attached = Room Lock). Authorization branches in the existing `DoorUnlocking` concern; Room Lock opens write `door_punches.room_entry = true` and skip bundle burn; Day Pool counting excludes room entries. Members reach the lock via new fields on `reservation_json` + an Unlock button on the mobile booking card. Config = `door_ids` on room update (web form + mobile admin). BLE auto-unlock rejects Room Locks (V1).

**Tech Stack:** Rails (minitest), React Native/Expo (jest). Docs: `CONTEXT.md` "Doors & Access", `docs/adr/0021-…`.

**Repos/branches:** new-jellyswitch — continue on `docs/room-locks-domain` (worktree `/private/tmp/claude-501/-Users-DavidOrr-Downloads-jellyswitch-mobile/f3feb882-5b4f-49d0-b173-b2ae076919fe/scratchpad/nj-room-locks`; PR #565 grows from docs-only to the full feature). jellyswitch-mobile — new branch `feature/room-locks` off origin/main.

**Backend test invocation:** `export PATH="$HOME/.rbenv/shims:$PATH" && PARALLEL_WORKERS=1 bin/rails test <paths>` (PARALLEL_WORKERS=1 avoids a macOS pg fork segfault; if a run wedges >3min, kill and rerun).

---

### Task 1: Schema + associations (`doors.room_id`, `door_punches.room_entry`)

**Files:**
- Create: `db/migrate/<timestamp>_add_room_to_doors.rb` (use `bin/rails g migration AddRoomToDoors` then fill in)
- Create: `db/migrate/<timestamp>_add_room_entry_to_door_punches.rb`
- Modify: `app/models/door.rb` (associations + predicate)
- Modify: `app/models/room.rb` (has_many :doors)
- Test: `test/models/door_test.rb` (append; create if absent)

- [ ] **Step 1: Write the failing test**

```ruby
require "test_helper"

class DoorRoomLockTest < ActiveSupport::TestCase
  test "a door attached to a room is that room's lock" do
    door = doors(:front_door) # any fixture door; adjust name after `grep -m1 ':' test/fixtures/doors.yml`
    refute door.room_lock?, "unattached door is a Building Door"

    door.update!(room: rooms(:small_meeting_room))
    assert door.room_lock?
    assert_includes rooms(:small_meeting_room).doors, door
  end
end
```

(If `test/fixtures/doors.yml` has different fixture names, use the first one — report the name used.)

- [ ] **Step 2: Run to verify it fails**

Run: `PARALLEL_WORKERS=1 bin/rails test test/models/door_test.rb`
Expected: error — `room_lock?` undefined / unknown attribute `room`

- [ ] **Step 3: Migrations**

```ruby
class AddRoomToDoors < ActiveRecord::Migration[7.2]
  def change
    # ADR 0021: a Door attached to a Room IS that Room's lock — the
    # attachment is the classification (no door-type enum).
    add_reference :doors, :room, null: true, foreign_key: true, index: true
  end
end
```

```ruby
class AddRoomEntryToDoorPunches < ActiveRecord::Migration[7.2]
  def change
    # Room Entry ≠ door punch (ADR 0021): Room Lock opens are audited in the
    # same table but flagged out of every "member entered the building"
    # semantic (Day Pool, bundle burn-on-entry, entry analytics).
    add_column :door_punches, :room_entry, :boolean, default: false, null: false
  end
end
```

Run: `bin/rails db:migrate` (development), and the test DB picks it up via schema on the next test run.

- [ ] **Step 4: Associations**

`app/models/door.rb` — under `belongs_to :location`:

```ruby
  # ADR 0021: attached to a Room ⇒ this door is that Room's LOCK —
  # reservation-gated, not coverage-gated. nil ⇒ Building Door.
  belongs_to :room, optional: true

  def room_lock?
    room_id.present?
  end
```

`app/models/room.rb` — under `has_many :amenities…`:

```ruby
  # Electric locks protecting this room (ADR 0021). Nullify, not destroy:
  # detaching a room's lock demotes the door to a Building Door.
  has_many :doors, dependent: :nullify
```

- [ ] **Step 5: Run to verify it passes, then commit**

Run: `PARALLEL_WORKERS=1 bin/rails test test/models/door_test.rb` — Expected: PASS

```bash
git add db/migrate db/schema.rb app/models/door.rb app/models/room.rb test/models/door_test.rb
git commit -m "feat: doors.room_id — attachment classifies a Room Lock (ADR 0021)"
```

---

### Task 2: Room Lock authorization in `DoorUnlocking`

**Files:**
- Modify: `app/controllers/concerns/api/v1/door_unlocking.rb`
- Test: covered by Task 4's request tests (concern is exercised through the controllers; repo pattern)

- [ ] **Step 1: Add the authorization method + constant**

Below `user_can_access_building?`:

```ruby
  ROOM_LOCK_EARLY_GRACE = 10.minutes

  # ADR 0021: a Room Lock opens for staff anytime, or the reservation
  # holder during their booking — including up to ROOM_LOCK_EARLY_GRACE
  # early, but only when no other booking still occupies the room (early
  # building entry is hospitality; early ROOM entry collides with the
  # previous meeting).
  def user_can_open_room_lock?(user, door)
    return false if user.nil? || door.room.nil?
    return true if user.superadmin?

    location = door.location
    return true if location && user.admin_or_manager?(location)

    now = Time.current
    holder_res = door.room.reservations
      .where(user: user, cancelled: false)
      .where("datetime_in <= ? AND (datetime_in + minutes * interval '1 minute') > ?",
             now + ROOM_LOCK_EARLY_GRACE, now)
      .order(:datetime_in)
      .first
    return false unless holder_res

    # Booking hasn't started yet (we're inside the grace window): the room
    # must actually be free — a still-running prior booking wins.
    if holder_res.datetime_in > now
      occupied = door.room.reservations
        .where(cancelled: false).where.not(id: holder_res.id)
        .where("datetime_in <= ? AND (datetime_in + minutes * interval '1 minute') > ?", now, now)
        .exists?
      return !occupied
    end

    true
  end
```

- [ ] **Step 2: Room Entry handling in `perform_unlock`**

Replace the existing `perform_unlock`:

```ruby
  def perform_unlock(door:, user:, location:, method:)
    room_entry = door.room_lock?
    DoorPunch.create!(user: user, door: door, operator: current_tenant, method: method, room_entry: room_entry)
    # Bundle burn-on-entry is a BUILDING-entry semantic — a Room Entry
    # never spends a pass (ADR 0021; the holder's reservation already
    # granted access anyway).
    unless room_entry
      begin
        Billing::DayPassBundles::ConsumeOnEntry.call(user: user, location: location)
      rescue => e
        Rails.logger.error("[DoorUnlocking] ConsumeOnEntry failed: #{e.class}: #{e.message}")
        Honeybadger.notify(e) rescue nil
      end
    end
    response = call_kisi_unlock(door, location)
    DoorPunch.create!(user: user, door: door, operator: current_tenant, method: method, json: response, room_entry: room_entry)
    response
  end
```

- [ ] **Step 3: Commit**

```bash
git add app/controllers/concerns/api/v1/door_unlocking.rb
git commit -m "feat: room-lock authorization + Room Entry punches skip bundle burn"
```

---

### Task 3: `doors#unlock` branches on door kind; `doors#index` hides Room Locks

**Files:**
- Modify: `app/controllers/api/v1/doors_controller.rb`
- Test: `test/controllers/api/v1/room_lock_unlock_test.rb` (create — written in Task 4 with the full matrix; this task is implementation-first because Task 4's tests need Kisi stubbed, shown there)

- [ ] **Step 1: `#unlock` authorization branch**

Replace the `unless user_can_access_building?…` guard block in `#unlock` with:

```ruby
    if door.room_lock?
      unless user_can_open_room_lock?(user, door)
        return render json: {
          success: false,
          door:    door.name,
          message: "#{door.room.name} opens with a reservation. Book the room to unlock it.",
        }, status: :forbidden
      end
    else
      unless user_can_access_building?(user, location)
        return render json: {
          success: false,
          door:    door.name,
          message: "You don't have access today. Buy a day pass or activate a membership to unlock the doors.",
        }, status: :forbidden
      end
    end
```

- [ ] **Step 2: `#index` filter**

After the existing `doors = doors.where(private: [false, nil]) unless current_api_user.admin?` line add:

```ruby
    # Room Locks never render in the general Keys list — the reservation is
    # the key (ADR 0021). Staff keep the full door list.
    doors = doors.where(room_id: nil) unless current_api_user.admin?
```

- [ ] **Step 3: Commit**

```bash
git add app/controllers/api/v1/doors_controller.rb
git commit -m "feat: room locks unlock via reservation; hidden from members' Keys list"
```

---

### Task 4: Request tests — the authorization matrix

**Files:**
- Create: `test/controllers/api/v1/room_lock_unlock_test.rb`

- [ ] **Step 1: Write the tests**

```ruby
require "test_helper"

# ADR 0021 authorization matrix for Room Locks (doors attached to a Room):
# holder-during-booking + staff only; coverage alone opens Building Doors
# but never a Room Lock; Room Entries don't burn bundle passes.
class Api::V1::RoomLockUnlockTest < ActionDispatch::IntegrationTest
  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @member   = users(:cowork_tahoe_member)
    @admin    = users(:cowork_tahoe_admin)
    @room     = rooms(:small_meeting_room)
    @room.reservations.delete_all

    @lock = Door.create!(name: "Meeting Room Lock", operator: @operator,
                         location: @location, room: @room, kisi_id: 99999, available: true)

    # Unlock hits Kisi — stub the client so tests don't do network I/O.
    Kisi::Client.stubs(:unlock).returns({ parsed: { "ok" => true } })
  end

  def headers_for(user)
    token = JWT.encode({ user_id: user.id, operator_id: @operator.id, exp: 30.days.from_now.to_i },
                       Rails.application.secret_key_base, "HS256")
    { "Authorization" => "Bearer #{token}", "X-Operator-Subdomain" => @operator.subdomain }
  end

  def reserve(user, starts_at, minutes: 60)
    Reservation.create!(user: user, room: @room, datetime_in: starts_at, minutes: minutes)
  end

  test "covered member WITHOUT a reservation cannot open a room lock" do
    post "/api/v1/doors/#{@lock.id}/unlock", headers: headers_for(@member)
    assert_response :forbidden
    assert_match(/opens with a reservation/, JSON.parse(response.body)["message"])
  end

  test "the reservation holder opens the lock during their booking" do
    reserve(@member, 10.minutes.ago)
    post "/api/v1/doors/#{@lock.id}/unlock", headers: headers_for(@member)
    assert_response :success
    assert JSON.parse(response.body)["success"]
  end

  test "holder within the early grace opens the lock when the room is free" do
    reserve(@member, 5.minutes.from_now)
    post "/api/v1/doors/#{@lock.id}/unlock", headers: headers_for(@member)
    assert_response :success
  end

  test "early grace is denied while a prior booking still occupies the room" do
    reserve(@admin, 30.minutes.ago, minutes: 40)   # still running
    reserve(@member, 5.minutes.from_now)
    post "/api/v1/doors/#{@lock.id}/unlock", headers: headers_for(@member)
    assert_response :forbidden
  end

  test "the holder cannot open the lock after their booking ends" do
    reserve(@member, 2.hours.ago, minutes: 60)
    post "/api/v1/doors/#{@lock.id}/unlock", headers: headers_for(@member)
    assert_response :forbidden
  end

  test "staff open a room lock anytime" do
    post "/api/v1/doors/#{@lock.id}/unlock", headers: headers_for(@admin)
    assert_response :success
  end

  test "a room-lock open is a Room Entry and never burns a bundle pass" do
    reserve(@member, 10.minutes.ago)
    Billing::DayPassBundles::ConsumeOnEntry.expects(:call).never

    post "/api/v1/doors/#{@lock.id}/unlock", headers: headers_for(@member)
    assert_response :success
    assert DoorPunch.where(door: @lock, user: @member).all?(&:room_entry),
      "room-lock punches must be flagged room_entry"
  end

  test "building doors keep coverage gating and punch semantics" do
    building_door = Door.create!(name: "Front", operator: @operator,
                                 location: @location, kisi_id: 99998, available: true)
    post "/api/v1/doors/#{building_door.id}/unlock", headers: headers_for(@member)
    assert_response :success
    refute DoorPunch.where(door: building_door, user: @member).any?(&:room_entry)
  end

  test "members' Keys list excludes room locks; admins keep them" do
    get "/api/v1/doors", headers: headers_for(@member)
    refute_includes JSON.parse(response.body).map { |d| d["id"] }, @lock.id

    get "/api/v1/doors", headers: headers_for(@admin)
    assert_includes JSON.parse(response.body).map { |d| d["id"] }, @lock.id
  end
end
```

(If `Kisi::Client.stubs` needs the door-specific arg or mocha isn't set up this way in the repo, mirror how existing door tests stub Kisi — check `test/controllers/api/v1/doors_controller_test.rb` first and follow its pattern; report any adaptation.)

- [ ] **Step 2: Run**

Run: `PARALLEL_WORKERS=1 bin/rails test test/controllers/api/v1/room_lock_unlock_test.rb`
Expected: 9 runs, 0 failures. (Note: the member has an active subscription fixture, which is what makes the building-door test pass — coverage.)

- [ ] **Step 3: Commit**

```bash
git add test/controllers/api/v1/room_lock_unlock_test.rb
git commit -m "test: room-lock authorization matrix"
```

---

### Task 5: BLE auto-unlock rejects Room Locks

**Files:**
- Modify: `app/controllers/api/v1/auto_unlocks_controller.rb` (after the `door.kisi_id.blank?` guard)
- Test: append to `test/controllers/api/v1/room_lock_unlock_test.rb`

- [ ] **Step 1: Guard**

```ruby
    # V1: Room Locks are excluded from approach-unlock (ADR 0021) — the
    # reservation card is the room's key; auto-popping a meeting-room door
    # for anyone walking past is wrong for non-holders and creepy for holders.
    return render_error("This door opens from your reservation, not by approach") if door.room_lock?
```

- [ ] **Step 2: Test (append to the Task 4 file)**

```ruby
  test "auto-unlock rejects room locks" do
    beacon = Beacon.create!(operator: @operator, location: @location, door: @lock,
                            uuid: "AAAA", major: 1, minor: 2, available: true)
    post "/api/v1/door/auto_unlock",
         params: { uuid: beacon.uuid, major: 1, minor: 2, nonce: SecureRandom.hex(8) },
         headers: headers_for(@member)
    assert_response :unprocessable_entity
    assert_match(/reservation/, JSON.parse(response.body)["error"])
  end
```

(Check `test/fixtures/beacons.yml` / the Beacon model for required fields; adapt creation minimally and report.)

- [ ] **Step 3: Run + commit**

Run: the Task 4 file again — Expected: 10 runs green.

```bash
git add app/controllers/api/v1/auto_unlocks_controller.rb test/controllers/api/v1/room_lock_unlock_test.rb
git commit -m "feat: BLE approach-unlock excludes room locks (V1)"
```

---

### Task 6: Day Pool + entry analytics exclude Room Entries

**Files:**
- Modify: `app/models/subscription.rb` — `day_pool_used` (~line 125) and `used_day_today?` (~line 163)
- Grep first: `grep -rn "door_punches" app/ lib/ | grep -v room_entry` — any OTHER site that counts punches as entries/visits (the day_pool comment says "mirrors UsageReport"; find it) gets the same `.where(room_entry: false)` filter. Do NOT touch pure audit/log listings (admin activity feeds, punches lists — those should show everything).
- Test: `test/models/day_pool_room_entry_test.rb` (create)

- [ ] **Step 1: Failing test**

```ruby
require "test_helper"

class DayPoolRoomEntryTest < ActiveSupport::TestCase
  test "room entries never count against the Day Pool" do
    member = users(:cowork_tahoe_member)
    sub = member.subscriptions.detect(&:active?)
    skip "fixture member has no active subscription" unless sub
    sub.plan.update!(has_day_limit: true, day_limit: 10)

    room = rooms(:small_meeting_room)
    lock = Door.create!(name: "Lock", operator: sub.operator,
                        location: sub.plan.location, room: room, available: true)
    front = Door.create!(name: "Front", operator: sub.operator,
                         location: sub.plan.location, available: true)

    used_before = sub.day_pool_used
    DoorPunch.create!(user: member, door: lock, operator: sub.operator, room_entry: true)
    assert_equal used_before, sub.reload.day_pool_used, "room entry burned a Day Pool day"

    DoorPunch.create!(user: member, door: front, operator: sub.operator)
    assert_equal used_before + 1, sub.reload.day_pool_used
  end
end
```

(Adapt `sub.plan.location` if the plan/location wiring differs — the intent is both doors at the Day Pool location; read `Subscription#day_pool_location` and report adjustments.)

- [ ] **Step 2: Run to verify it fails** (the room-entry punch currently counts)

- [ ] **Step 3: Implement**

In `day_pool_used`, add `.where(room_entry: false)` to the `subscribable.door_punches` chain (exact placement: alongside the existing `.where(doors: { location_id: … })`), with the comment:

```ruby
      # Room Entries are not building entries (ADR 0021) — only Building
      # Door punches burn Day Pool days.
```

Apply the same filter in `used_day_today?` and in the UsageReport counterpart found by the grep.

- [ ] **Step 4: Run to verify green, run `test/models/` for regressions, commit**

```bash
git add app/models/subscription.rb test/models/day_pool_room_entry_test.rb <any UsageReport file>
git commit -m "feat: Day Pool and entry analytics ignore Room Entries"
```

---

### Task 7: The reservation carries its key (`reservation_json`)

**Files:**
- Modify: `app/controllers/api/v1/reservations_controller.rb` — `reservation_json` (~line 385)
- Test: `test/controllers/api/v1/reservation_room_door_test.rb` (create)

- [ ] **Step 1: Failing test**

```ruby
require "test_helper"

# "The reservation is the key" (ADR 0021): the booking payload carries its
# room's lock + whether it is unlockable right now, so the app renders the
# Unlock button on the booking card.
class Api::V1::ReservationRoomDoorTest < ActionDispatch::IntegrationTest
  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @member   = users(:cowork_tahoe_member)
    @room     = rooms(:small_meeting_room)
    @room.reservations.delete_all
    @lock = Door.create!(name: "Meeting Room Lock", operator: @operator,
                         location: @location, room: @room, kisi_id: 99997, available: true)
    @token = JWT.encode({ user_id: @member.id, operator_id: @operator.id, exp: 30.days.from_now.to_i },
                        Rails.application.secret_key_base, "HS256")
  end

  def headers
    { "Authorization" => "Bearer #{@token}", "X-Operator-Subdomain" => @operator.subdomain }
  end

  test "an ongoing reservation exposes its unlockable room door" do
    Reservation.create!(user: @member, room: @room, datetime_in: 10.minutes.ago, minutes: 60)
    get "/api/v1/reservations", headers: headers
    res = JSON.parse(response.body).find { |r| r["room_id"] == @room.id }
    assert_equal @lock.id, res["room_door_id"]
    assert_equal true, res["room_door_unlockable"]
  end

  test "a far-future reservation carries the door but not unlockable" do
    Reservation.create!(user: @member, room: @room, datetime_in: 3.hours.from_now, minutes: 60)
    get "/api/v1/reservations", headers: headers
    res = JSON.parse(response.body).find { |r| r["room_id"] == @room.id }
    assert_equal @lock.id, res["room_door_id"]
    assert_equal false, res["room_door_unlockable"]
  end
end
```

(Check how `/api/v1/reservations` index shapes its body — if it nests under a key, adapt the parse; report.)

- [ ] **Step 2: Implement in `reservation_json`**

Inside the hash (after `minutes_remaining:`), add:

```ruby
      # "The reservation is the key" (ADR 0021). room_door_unlockable is the
      # optimistic client signal (ongoing, or starting within the grace);
      # the unlock endpoint re-checks for a still-occupying prior booking.
      room_door_id: room_door(r)&.id,
      room_door_name: room_door(r)&.name,
      room_door_unlockable: !r.cancelled && room_door(r).present? &&
        (ongoing || (future && r.datetime_in <= now + Api::V1::DoorUnlocking::ROOM_LOCK_EARLY_GRACE)),
```

And a private helper next to `reservation_json`:

```ruby
    def room_door(r)
      # memoize per reservation id — reservation_json runs in a list loop
      @room_doors ||= {}
      @room_doors[r.room_id] ||= r.room.doors.where(available: true).where.not(kisi_id: nil).first
    end
```

- [ ] **Step 3: Run, then commit**

```bash
git add app/controllers/api/v1/reservations_controller.rb test/controllers/api/v1/reservation_room_door_test.rb
git commit -m "feat: reservation payload carries its room lock (the reservation is the key)"
```

---

### Task 8: Door↔Room configuration (admin API + web room form)

**Files:**
- Modify: `app/controllers/api/v1/admin/rooms_controller.rb` (`#update`, `#room_json`)
- Modify: `app/controllers/api/v1/admin/doors_controller.rb` if it exists (check `ls app/controllers/api/v1/admin/ | grep door`) — if it has an index, include `room_id`/`room_name` in its payload; otherwise skip
- Modify: `app/controllers/operator/rooms_controller.rb` + `app/views/operator/rooms/_form_fields.html.erb`
- Test: `test/controllers/api/v1/admin/rooms_doors_test.rb` (create)

- [ ] **Step 1: Failing test**

```ruby
require "test_helper"

class Api::V1::Admin::RoomsDoorsTest < ActionDispatch::IntegrationTest
  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @admin    = users(:cowork_tahoe_admin)
    @room     = rooms(:small_meeting_room)
    @door     = Door.create!(name: "Lock A", operator: @operator, location: @location, available: true)
    @token = JWT.encode({ user_id: @admin.id, operator_id: @operator.id, exp: 30.days.from_now.to_i },
                        Rails.application.secret_key_base, "HS256")
  end

  def headers
    { "Authorization" => "Bearer #{@token}", "X-Operator-Subdomain" => @operator.subdomain,
      "Content-Type" => "application/json" }
  end

  test "assigning and clearing a room's locks via door_ids" do
    patch "/api/v1/admin/rooms/#{@room.id}",
          params: { room: { door_ids: [@door.id] } }.to_json, headers: headers
    assert_response :success
    assert_equal @room.id, @door.reload.room_id
    assert_includes JSON.parse(response.body)["door_ids"], @door.id

    patch "/api/v1/admin/rooms/#{@room.id}",
          params: { room: { door_ids: [] } }.to_json, headers: headers
    assert_nil @door.reload.room_id
  end

  test "cannot attach another location's door" do
    other = locations(:cowork_tahoe_location) # replace with a second-location fixture if one exists; otherwise create a Location minimally and report
    skip "needs a second location fixture" if other.id == @location.id
  end
end
```

(For the second test: check `test/fixtures/locations.yml` for a second location; if none exists cheaply, drop the test and rely on the scoped query below — report the choice.)

- [ ] **Step 2: Implement — admin API**

In `Api::V1::Admin::RoomsController#update`, before the `if room.update(room_params)`:

```ruby
    # Door↔Room attachment (ADR 0021). Reassignment is scoped to the room's
    # location so a lock can never be attached across locations. Sent as the
    # full list: doors omitted are detached (become Building Doors again).
    if params[:room].key?(:door_ids)
      ids = Array(params[:room][:door_ids]).map(&:to_i)
      scope = Door.where(operator: current_tenant, location: room.location)
      scope.where(room_id: room.id).where.not(id: ids).update_all(room_id: nil)
      scope.where(id: ids).update_all(room_id: room.id)
    end
```

Add to `room_json`: `door_ids: room.doors.pluck(:id),`

- [ ] **Step 3: Implement — web room form**

In `app/views/operator/rooms/_form_fields.html.erb`, after the `:visible` checkbox block:

```erb
  <div class="form-group mt-3">
    <label>Door locks</label>
    <p class="text-muted small mb-1">
      Attach this room's electric lock(s). An attached door opens only for the
      reservation holder during their booking (and staff) — not for general members.
    </p>
    <% current_location.doors.where(available: true).order(:name).each do |door| %>
      <div class="form-check">
        <%= check_box_tag "room[door_ids][]", door.id,
              door.room_id == f.object.id,
              id: "room_door_#{door.id}", class: "form-check-input" %>
        <%= label_tag "room_door_#{door.id}", door.name, class: "form-check-label" %>
        <% if door.room_id.present? && door.room_id != f.object.id %>
          <small class="text-muted">(currently: <%= door.room&.name %>)</small>
        <% end %>
      </div>
    <% end %>
    <%# Hidden empty entry so unchecking ALL boxes still submits door_ids %>
    <%= hidden_field_tag "room[door_ids][]", "" %>
  </div>
```

In `Operator::RoomsController#update` (and `#create` after `@room.save` succeeds), apply the same reassignment block as the admin API (using `current_tenant` and `@room`), guarded by `params[:room]&.key?(:door_ids)` — and REJECT blank ids: `ids = Array(params[:room][:door_ids]).reject(&:blank?).map(&:to_i)`. Use `.reject(&:blank?)` in the admin API version too.

- [ ] **Step 4: Run + commit**

Run: the new test + `PARALLEL_WORKERS=1 bin/rails test test/controllers/operator/rooms_controller_test.rb`

```bash
git add app/controllers/api/v1/admin/rooms_controller.rb app/controllers/operator/rooms_controller.rb app/views/operator/rooms/_form_fields.html.erb test/controllers/api/v1/admin/rooms_doors_test.rb
git commit -m "feat: attach door locks to a room from room settings (web + admin API)"
```

---

### Task 9: Mobile — Unlock button on the booking card + admin room door picker

Work in `/Users/DavidOrr/Downloads/jellyswitch-mobile`: `git fetch origin -q && git checkout -b feature/room-locks origin/main`. After each change: babel parse-check the touched file + `npx jest` (expect 138/138; no jest additions here — this is pure wiring against server-tested fields).

**Files:**
- Modify: `src/screens/book/MyReservationsScreen.js`
- Modify: `src/screens/admin/AdminRoomsScreen.js`
- Reference (read, don't modify): `src/api/client.js` — `doorsAPI.unlock(doorId)` and `adminRoomsAPI.update` already exist; `adminDoorsAPI`/doors list for admin — check what exists (`grep -n "doorsAPI\|adminDoorsAPI" src/api/client.js`) and report if a doors-list call for admins is missing (if so add `list: () => client.get('/doors')` usage — admins get all doors from the same endpoint per Task 3).

- [ ] **Step 1: Unlock button on the reservation card**

Read `MyReservationsScreen.js` first; find the ongoing/upcoming card's action row (near the Extend/End/Edit buttons). Add, for items where `item.room_door_id && item.room_door_unlockable`:

```jsx
              {item.room_door_id && item.room_door_unlockable && (
                <Button
                  title={`Unlock ${item.room_door_name || 'Room'}`}
                  size="sm"
                  onPress={() => handleUnlockRoom(item)}
                  loading={unlockingId === item.id}
                />
              )}
```

With handler + state (mirror the screen's existing handler style):

```javascript
  const [unlockingId, setUnlockingId] = useState(null);

  // "The reservation is the key" — the room's lock unlocks from the booking
  // card during the reservation window. The server re-checks authorization
  // (holder + window + room actually free), so a stale button fails safe.
  const handleUnlockRoom = async (item) => {
    setUnlockingId(item.id);
    try {
      const res = await doorsAPI.unlock(item.room_door_id);
      Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
      Alert.alert('Unlocked', res.data?.message || `${item.room_door_name || 'Room'} unlocked.`);
    } catch (e) {
      Haptics.notificationAsync(Haptics.NotificationFeedbackType.Error);
      Alert.alert('Could not unlock', e.response?.data?.message || 'Please try again.');
    } finally {
      setUnlockingId(null);
    }
  };
```

Import `doorsAPI` (check the screen's existing import from `../../api/client` and extend it). If the screen lacks `Haptics`, import `* as Haptics from 'expo-haptics'` (match sibling screens).

- [ ] **Step 2: Admin room form door picker**

Read `AdminRoomsScreen.js` (the edit form around the `visible` Switch). Add a "DOOR LOCKS" section listing the location's doors as toggle chips; fetch doors lazily when the form opens via the doors endpoint identified above; selected = `formData.door_ids` (initialize from `room.door_ids` in the edit payload — Task 8 added it to `room_json`); include `door_ids` in the update call. Match the screen's existing form patterns exactly (this screen already has array-ish fields — features/tags — copy that pattern). Include the explanatory caption: `Attached doors open only for the reservation holder during their booking (and staff).`

- [ ] **Step 3: Parse-check + jest + commit**

```bash
git add src/screens/book/MyReservationsScreen.js src/screens/admin/AdminRoomsScreen.js src/api/client.js
git commit -m "feat: booking-card room unlock + door locks in admin room config"
```

---

### Task 10: Ship + TLH attachment

- [ ] **Step 1:** Backend: full targeted suites (`test/models/ test/controllers/api/v1/ test/controllers/operator/rooms_controller_test.rb`) green (ignore the known local `STRIPE_SECRET_KEY` env errors in operator users tests); push `docs/room-locks-domain`; update PR #565 title to "Room Locks: reservation-gated interior doors (ADR 0021)" and body to cover the implementation; wait for CI (watch with a failure-covering watcher; the queue can sit for hours — report still-queued).
- [ ] **Step 2:** Mobile: push `feature/room-locks`, open PR referencing #565, jest green.
- [ ] **Step 3:** Merge backend first (auto-deploys), then mobile, then OTA all 4 brands:

```bash
for b in untethered cowork-tahoe choose-folsom tahoelonghouse; do
  BRAND=$b npx eas update --channel production --non-interactive --message "room locks: reservation is the key"
done
```

- [ ] **Step 4:** TLH data attachment (after backend deploy; read-only-verified first):

```bash
heroku run --no-tty -a jellyswitch-production rails runner \
  'd = Door.find(2655); d.update!(room_id: 6169); puts "#{d.name} -> #{d.room.name}"'
```

Booths (2658-2661 incl. Studio A) stay unattached (walk-up) pending TLH's answer on Studio A. Verify: member without a booking gets the "opens with a reservation" message on door 2655; staff unlock works.

---

## Self-review notes

- Spec coverage: attachment+migration (T1), auth (T2-T4), BLE exclusion (T5), Room Entry semantics (T2 punch flag + T6 Day Pool/analytics), Keys filtering (T3), reservation-as-key (T7 API + T9 mobile), config (T8 web+API, T9 mobile), TLH data (T10). Matches ADR 0021 + CONTEXT.
- Known repo facts encoded: `perform_unlock` writes TWO punches (pre + post Kisi) — both flagged; `user_can_access_building?` unchanged (Guard 3 all-day building access via reservation is BUILDING behavior, untouched); auto-unlock's separate punch path never reaches room locks (rejected before).
- Type consistency: `room_lock?` (T1) used in T2/T3/T5; `room_door_id`/`room_door_name`/`room_door_unlockable` (T7) consumed in T9; `door_ids` (T8) consumed in T9; `ROOM_LOCK_EARLY_GRACE` defined T2, referenced T7.
- Implementer latitude is explicitly bounded: fixture names, Kisi stub style, beacon fields, reservations-index body shape — verify-and-report, not guess.
