# Reserve Later Refinement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Hour/:30/:15 start-time granularity chips (default Hour), honest 409 conflict errors with one-tap room refresh, and a polish pass on the mobile Reserve Later screen.

**Architecture:** Backend tags the existing `ReservationValidator` overlap error, threads a `conflict` flag through the create/update interactors, and renders HTTP 409 with `{error, conflict: {room_name, window_label}}`. Mobile adds a pure `src/utils/reserveLater.js` (granularity filter, confirm label, conflict parser — all jest-tested) and wires it into `ReserveLaterScreen`. No new endpoints; granularity is a client-side filter over the existing 15-min grid.

**Tech Stack:** Rails (minitest), React Native/Expo (jest). Spec: `docs/superpowers/specs/2026-07-02-reserve-later-refinement-design.md`.

**Repos/branches:** new-jellyswitch `feature/reserve-later-refinement` (worktree already exists); jellyswitch-mobile — create branch `feature/reserve-later-refinement` off origin/main.

**Test invocation (backend):** `PATH="$HOME/.rbenv/shims:$PATH" PARALLEL_WORKERS=1 bin/rails test <path>` (PARALLEL_WORKERS=1 avoids a macOS pg fork segfault; CI is unaffected).

---

### Task 1: `Reservation#window_label` (backend)

The human window ("10:00–11:00 AM") in the room's location zone, shared by the validator message and the 409 payload.

**Files:**
- Modify: `app/models/reservation.rb` (instance methods section, near `def datetime_out`, ~line 112)
- Test: `test/models/reservation_window_label_test.rb` (create)

- [ ] **Step 1: Write the failing test**

```ruby
require "test_helper"

class ReservationWindowLabelTest < ActiveSupport::TestCase
  setup do
    @room = rooms(:small_meeting_room) # cowork_tahoe_location, Pacific
    @user = users(:cowork_tahoe_member)
  end

  def build_reservation(hour:, minutes:)
    zone = ActiveSupport::TimeZone[@room.location.time_zone]
    day = Date.current + 7
    Reservation.new(user: @user, room: @room,
      datetime_in: zone.local(day.year, day.month, day.day, hour), minutes: minutes)
  end

  test "same-meridiem window drops the duplicate AM/PM" do
    assert_equal "10:00–11:00 AM", build_reservation(hour: 10, minutes: 60).window_label
  end

  test "cross-meridiem window keeps both" do
    assert_equal "11:30 AM–1:00 PM", build_reservation(hour: 11, minutes: 90)
      .tap { |r| r.datetime_in = r.datetime_in.change(min: 30) }.window_label
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `PATH="$HOME/.rbenv/shims:$PATH" PARALLEL_WORKERS=1 bin/rails test test/models/reservation_window_label_test.rb`
Expected: FAIL / errors with `NoMethodError: undefined method 'window_label'`

- [ ] **Step 3: Implement**

In `app/models/reservation.rb`, directly under `def datetime_out … end`:

```ruby
  # "10:00–11:00 AM" in the room's location zone (datetime_in's reader already
  # presents the location zone). Drops the duplicate meridiem when both ends
  # share it. Used by ReservationValidator's overlap message and the API's
  # 409 conflict payload.
  def window_label
    starts = datetime_in
    ends = datetime_out
    if starts.strftime("%p") == ends.strftime("%p")
      "#{starts.strftime('%-l:%M')}–#{ends.strftime('%-l:%M %p')}"
    else
      "#{starts.strftime('%-l:%M %p')}–#{ends.strftime('%-l:%M %p')}"
    end
  end
```

- [ ] **Step 4: Run to verify it passes**

Run: same command. Expected: `2 runs, 2 assertions, 0 failures`

- [ ] **Step 5: Commit**

```bash
git add app/models/reservation.rb test/models/reservation_window_label_test.rb
git commit -m "feat: Reservation#window_label (location-zone human window)"
```

---

### Task 2: Precise, tagged overlap error in `ReservationValidator` (backend)

**Files:**
- Modify: `app/validators/reservation_validator.rb`
- Test: `test/validators/reservation_validator_test.rb` (create)

- [ ] **Step 1: Write the failing test**

```ruby
require "test_helper"

class ReservationValidatorTest < ActiveSupport::TestCase
  setup do
    @room = rooms(:small_meeting_room)
    @user = users(:cowork_tahoe_member)
    @zone = ActiveSupport::TimeZone[@room.location.time_zone]
    @room.reservations.delete_all
    day = Date.current + 7
    @start = @zone.local(day.year, day.month, day.day, 10)
    Reservation.create!(user: @user, room: @room, datetime_in: @start, minutes: 60)
  end

  test "overlap message names the room and the requested window" do
    clash = Reservation.new(user: @user, room: @room, datetime_in: @start, minutes: 60)
    refute clash.valid?
    assert_equal "#{@room.name} is no longer free 10:00–11:00 AM.",
      clash.errors.full_messages.first
  end

  test "overlap error is tagged :overlap in details" do
    clash = Reservation.new(user: @user, room: @room, datetime_in: @start, minutes: 30)
    clash.valid?
    assert clash.errors.details[:base].any? { |d| d[:error] == :overlap }
  end

  test "non-overlapping reservation stays valid" do
    free = Reservation.new(user: @user, room: @room,
      datetime_in: @start + 2.hours, minutes: 60)
    assert free.valid?
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `PATH="$HOME/.rbenv/shims:$PATH" PARALLEL_WORKERS=1 bin/rails test test/validators/reservation_validator_test.rb`
Expected: 2 failures (old generic message; no `:overlap` detail)

- [ ] **Step 3: Implement**

Replace the `if overlapping_reservations.exists?` branch in `app/validators/reservation_validator.rb`:

```ruby
    if overlapping_reservations.exists?
      # Precise + tagged: the message reaches members verbatim (old app
      # bundles render data.error raw), and the :overlap tag lets the API
      # detect a conflict and return 409 with a structured payload.
      record.errors.add(:base, :overlap,
        message: "#{record.room&.name || 'This room'} is no longer free #{record.window_label}.")
    end
```

- [ ] **Step 4: Run to verify it passes**

Run: same command. Expected: `3 runs, 0 failures`

- [ ] **Step 5: Commit**

```bash
git add app/validators/reservation_validator.rb test/validators/reservation_validator_test.rb
git commit -m "feat: overlap error names room + window, tagged :overlap"
```

---

### Task 3: Thread `conflict` through the interactors (backend)

**Files:**
- Modify: `app/interactors/billing/reservations/save_room_reservation.rb` (the `if !reservation.save` branch, ~line 35)
- Modify: `app/interactors/billing/reservations/update_room_reservation.rb` (the `unless reservation.save` branch, ~line 27)
- Test: covered end-to-end by Task 4's request tests (interactors have no isolated test files today; follow that pattern)

- [ ] **Step 1: SaveRoomReservation**

Replace:

```ruby
    if !reservation.save
      context.fail!(message: reservation.errors.full_messages.first || "Unable to create reservation, please try again.")
    end
```

with:

```ruby
    if !reservation.save
      # Overlap (someone booked between the room list loading and this tap)
      # is a CONFLICT, not a generic failure — the API returns 409 with the
      # room + window so the app can offer a one-tap list refresh.
      context.conflict = reservation.errors.details[:base].any? { |d| d[:error] == :overlap }
      context.fail!(message: reservation.errors.full_messages.first || "Unable to create reservation, please try again.")
    end
```

- [ ] **Step 2: UpdateRoomReservation**

Replace:

```ruby
    unless reservation.save
      context.fail!(error: reservation.errors.full_messages.first || "Could not update reservation.")
      return
    end
```

with:

```ruby
    unless reservation.save
      # See SaveRoomReservation: :overlap-tagged failures surface as 409.
      context.conflict = reservation.errors.details[:base].any? { |d| d[:error] == :overlap }
      context.fail!(error: reservation.errors.full_messages.first || "Could not update reservation.")
      return
    end
```

- [ ] **Step 3: Commit**

```bash
git add app/interactors/billing/reservations/save_room_reservation.rb app/interactors/billing/reservations/update_room_reservation.rb
git commit -m "feat: interactors flag overlap failures as conflicts"
```

---

### Task 4: 409 + structured payload from the API (backend)

**Files:**
- Modify: `app/controllers/api/v1/reservations_controller.rb` — `#create` failure branch (~line 92) and `#update` failure branch (~line 139), plus one private helper
- Test: `test/controllers/api/v1/reservations_conflict_test.rb` (create)

- [ ] **Step 1: Write the failing request test**

```ruby
require "test_helper"

# A room taken between the room list loading and the member's Confirm tap
# must come back as 409 + {error, conflict:{room_name, window_label}} — the
# app shows "Just missed it" and refreshes the list. Older bundles render
# data.error raw, so the sentence itself must carry room + window.
class Api::V1::ReservationsConflictTest < ActionDispatch::IntegrationTest
  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @member   = users(:cowork_tahoe_member)
    @rival    = users(:cowork_tahoe_admin)
    @room     = rooms(:small_meeting_room)
    @room.reservations.delete_all
    @zone = ActiveSupport::TimeZone[@location.time_zone]
    day = Date.current + 7
    @start = @zone.local(day.year, day.month, day.day, 10)
    Reservation.create!(user: @rival, room: @room, datetime_in: @start, minutes: 60)

    @token = JWT.encode({ user_id: @member.id, operator_id: @operator.id, exp: 30.days.from_now.to_i },
                        Rails.application.secret_key_base, "HS256")
  end

  def headers
    { "Authorization" => "Bearer #{@token}",
      "X-Operator-Subdomain" => @operator.subdomain,
      "Content-Type" => "application/json" }
  end

  test "create against a taken slot returns 409 with room + window" do
    post "/api/v1/reservations",
         params: { reservation: { room_id: @room.id,
                                  datetime_in: @start.strftime("%Y-%m-%dT%H:%M:%S"),
                                  minutes: 60 } }.to_json,
         headers: headers

    assert_response :conflict
    body = JSON.parse(response.body)
    assert_equal "#{@room.name} is no longer free 10:00–11:00 AM.", body["error"]
    assert_equal @room.name, body.dig("conflict", "room_name")
    assert_equal "10:00–11:00 AM", body.dig("conflict", "window_label")
  end

  test "update into a taken slot returns 409 with conflict payload" do
    mine = Reservation.create!(user: @member, room: @room,
      datetime_in: @start + 3.hours, minutes: 60)

    patch "/api/v1/reservations/#{mine.id}",
          params: { reservation: { datetime_in: @start.strftime("%Y-%m-%dT%H:%M:%S"),
                                   minutes: 60 } }.to_json,
          headers: headers

    assert_response :conflict
    body = JSON.parse(response.body)
    assert body.dig("conflict", "window_label").present?
    # The persisted row is untouched by the failed edit.
    assert_equal (@start + 3.hours).to_i, mine.reload.datetime_in.to_i
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `PATH="$HOME/.rbenv/shims:$PATH" PARALLEL_WORKERS=1 bin/rails test test/controllers/api/v1/reservations_conflict_test.rb`
Expected: FAIL — responses are 422 without `conflict`

- [ ] **Step 3: Implement the controller changes**

In `#create`, replace:

```ruby
    if result.success?
      render json: reservation_json(result.reservation), status: :created
    else
      render_error(result.message.presence || result.error || 'Booking failed')
    end
```

with:

```ruby
    if result.success?
      render json: reservation_json(result.reservation), status: :created
    elsif result.conflict
      render_conflict(result.message.presence || 'That room was just booked.', result.reservation)
    else
      render_error(result.message.presence || result.error || 'Booking failed')
    end
```

In `#update`, replace:

```ruby
    if result.success?
      render json: reservation_json(reservation.reload)
    else
      render_error(result.error || 'Could not update reservation')
    end
```

with:

```ruby
    if result.success?
      render json: reservation_json(reservation.reload)
    elsif result.conflict
      # The failed save left the new attrs assigned in-memory, so
      # window_label reflects the REQUESTED window, not the old one.
      render_conflict(result.error || 'That room was just booked.', reservation)
    else
      render_error(result.error || 'Could not update reservation')
    end
```

Add the private helper (next to `render_error` usage, bottom of the controller's private section):

```ruby
    # 409 for a room-time overlap. `error` doubles as the display sentence for
    # old app bundles that render data.error raw; `conflict` lets new bundles
    # style the "Just missed it" alert + refresh. `failed_reservation` is the
    # unsaved record carrying the requested room/window.
    def render_conflict(message, failed_reservation)
      render json: {
        error: message,
        conflict: {
          room_name: failed_reservation&.room&.name,
          window_label: failed_reservation&.window_label,
        },
      }, status: :conflict
    end
```

- [ ] **Step 4: Run to verify it passes**

Run: same command. Expected: `2 runs, 0 failures`
(If create-path coverage enforcement 422s first: the member fixture holds an active subscription, which covers included rooms — if the test still hits `needs day pass`, add `minutes: 60` day-pass coverage by asserting against the priced room `rooms(:large_meeting_room)` instead; adjust fixture per failure message.)

- [ ] **Step 5: Run the neighboring suites**

Run: `PATH="$HOME/.rbenv/shims:$PATH" PARALLEL_WORKERS=1 bin/rails test test/controllers/api/v1/reservations_controller_test.rb test/controllers/api/v1/reservations_coverage_test.rb test/interactors/billing/reservations/`
Expected: 0 failures

- [ ] **Step 6: Commit + push + PR**

```bash
git add app/controllers/api/v1/reservations_controller.rb test/controllers/api/v1/reservations_conflict_test.rb
git commit -m "feat: 409 + {room_name, window_label} on booking conflicts"
git push -u origin feature/reserve-later-refinement
gh pr create --title "Reserve Later: honest 409 conflict errors (room + window)" \
  --body "Backend half of docs/superpowers/specs/2026-07-02-reserve-later-refinement-design.md. Pairs with the jellyswitch-mobile PR."
```

---

### Task 5: Pure mobile helpers `src/utils/reserveLater.js` (mobile repo)

Work in `/Users/DavidOrr/Downloads/jellyswitch-mobile` on a new branch: `git checkout -b feature/reserve-later-refinement origin/main`.

**Files:**
- Create: `src/utils/reserveLater.js`
- Test: `tests/utils/reserveLater.test.js` (create)

- [ ] **Step 1: Write the failing tests**

```javascript
import {
  filterTimesByGranularity,
  confirmButtonLabel,
  conflictFromError,
} from '../../src/utils/reserveLater';

const GRID = [
  { time: '09:00', label: '9:00 AM' },
  { time: '09:15', label: '9:15 AM' },
  { time: '09:30', label: '9:30 AM' },
  { time: '09:45', label: '9:45 AM' },
  { time: '10:00', label: '10:00 AM' },
];

describe('filterTimesByGranularity', () => {
  test('60 keeps top-of-hour only (the default view)', () => {
    expect(filterTimesByGranularity(GRID, 60).map((t) => t.time)).toEqual(['09:00', '10:00']);
  });
  test('30 keeps :00 and :30', () => {
    expect(filterTimesByGranularity(GRID, 30).map((t) => t.time)).toEqual(['09:00', '09:30', '10:00']);
  });
  test('15 keeps everything', () => {
    expect(filterTimesByGranularity(GRID, 15)).toHaveLength(5);
  });
  test('tolerates empty/absent input', () => {
    expect(filterTimesByGranularity([], 60)).toEqual([]);
    expect(filterTimesByGranularity(null, 60)).toEqual([]);
  });
});

describe('confirmButtonLabel', () => {
  test('free booking states room and time', () => {
    expect(confirmButtonLabel({ isEditing: false, roomName: 'Meeting Room 3B', timeLabel: '10:00 AM', totalCents: 0 }))
      .toBe('Reserve Meeting Room 3B · 10:00 AM');
  });
  test('priced booking states room and price', () => {
    expect(confirmButtonLabel({ isEditing: false, roomName: 'Meeting Room 3B', timeLabel: '10:00 AM', totalCents: 1250 }))
      .toBe('Reserve Meeting Room 3B · $12.50');
  });
  test('editing keeps Save phrasing', () => {
    expect(confirmButtonLabel({ isEditing: true, roomName: 'Meeting Room 3B', timeLabel: '10:00 AM', totalCents: 0 }))
      .toBe('Save Changes');
    expect(confirmButtonLabel({ isEditing: true, roomName: 'Meeting Room 3B', timeLabel: '10:00 AM', totalCents: 500 }))
      .toBe('Save · $5.00');
  });
  test('no room selected falls back', () => {
    expect(confirmButtonLabel({ isEditing: false, roomName: null, timeLabel: '10:00 AM', totalCents: 0 }))
      .toBe('Confirm Booking');
  });
});

describe('conflictFromError', () => {
  test('409 with conflict payload is a conflict with the server sentence', () => {
    const e = { response: { status: 409, data: { error: 'Meeting Room 3B is no longer free 10:00–11:00 AM.', conflict: { room_name: 'Meeting Room 3B', window_label: '10:00–11:00 AM' } } } };
    expect(conflictFromError(e)).toEqual({
      isConflict: true,
      message: 'Meeting Room 3B is no longer free 10:00–11:00 AM.',
    });
  });
  test('non-409 errors are not conflicts and keep their message', () => {
    const e = { response: { status: 422, data: { error: 'Please provide payment method!' } } };
    expect(conflictFromError(e)).toEqual({ isConflict: false, message: 'Please provide payment method!' });
  });
  test('network errors degrade gracefully', () => {
    expect(conflictFromError({})).toEqual({ isConflict: false, message: null });
  });
});
```

- [ ] **Step 2: Run to verify they fail**

Run: `npx jest tests/utils/reserveLater.test.js`
Expected: FAIL — module not found

- [ ] **Step 3: Implement**

```javascript
// Pure helpers for the Reserve Later screen — kept out of the component so
// jest can cover them without rendering.

// Granularity chips (Hour/:30/:15) filter the server's 15-min start grid
// client-side. `times` entries are { time: "HH:MM", ... }.
export function filterTimesByGranularity(times, granularityMinutes) {
  if (!Array.isArray(times)) return [];
  if (granularityMinutes >= 60) return times.filter((t) => t.time?.endsWith(':00'));
  if (granularityMinutes >= 30) return times.filter((t) => /:(00|30)$/.test(t.time || ''));
  return times;
}

// Confirm button says what it does: the room + time when free, the room +
// price when money moves. Edit mode keeps its established Save phrasing.
export function confirmButtonLabel({ isEditing, roomName, timeLabel, totalCents }) {
  const price = totalCents > 0 ? `$${(totalCents / 100).toFixed(2)}` : null;
  if (isEditing) return price ? `Save · ${price}` : 'Save Changes';
  if (!roomName) return price ? `Confirm · ${price}` : 'Confirm Booking';
  return `Reserve ${roomName} · ${price || timeLabel}`;
}

// A booking failure is a CONFLICT when the server said 409 (room taken
// between list-load and confirm). The server sentence already names the
// room + window — show it verbatim.
export function conflictFromError(e) {
  const status = e?.response?.status;
  const data = e?.response?.data;
  return {
    isConflict: status === 409 && !!data?.conflict,
    message: data?.error || null,
  };
}
```

- [ ] **Step 4: Run to verify they pass**

Run: `npx jest tests/utils/reserveLater.test.js`
Expected: all pass

- [ ] **Step 5: Commit**

```bash
git add src/utils/reserveLater.js tests/utils/reserveLater.test.js
git commit -m "feat: reserve-later helpers (granularity filter, confirm label, conflict parse)"
```

---

### Task 6: Granularity chips in ReserveLaterScreen (mobile)

**Files:**
- Modify: `src/screens/book/ReserveLaterScreen.js` — import block (~line 22), state (~line 99), the TIME section (~lines 367–399)

- [ ] **Step 1: Import + state**

Add to imports:

```javascript
import { filterTimesByGranularity, confirmButtonLabel, conflictFromError } from '../../utils/reserveLater';
```

Add state next to the other pickers (`const [duration, setDuration] = …`):

```javascript
  // Start-time granularity (Hour/:30/:15). Default Hour: most bookings start
  // top-of-the-hour, and the full 15-min grid is a wall of ~40 chips.
  const [granularity, setGranularity] = useState(60);
```

- [ ] **Step 2: Filter + selection preservation**

Where `timeChips` is rendered (the `timeChips.map(...)` at ~line 381), render a filtered list instead. Above the TIME section's JSX add:

```javascript
  const visibleTimeChips = filterTimesByGranularity(timeChips, granularity);
```

And add a granularity-change handler near the other handlers:

```javascript
  const changeGranularity = (g) => {
    setGranularity(g);
    // Keep the selected time if it survives the coarser grid; otherwise
    // clear it (the rooms list resets via the existing effect).
    if (selectedTime && !filterTimesByGranularity(timeChips, g).some((t) => t.time === selectedTime)) {
      setSelectedTime(null);
    }
    Haptics.selectionAsync();
  };
```

- [ ] **Step 3: The chips row**

Replace the TIME label line (`<Text style={[typography.label, { marginTop: spacing.lg }]}>TIME</Text>`) with:

```jsx
        <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginTop: spacing.lg }}>
          <Text style={typography.label}>TIME</Text>
          <View style={{ flexDirection: 'row', gap: 6 }}>
            {[{ g: 60, label: 'Hour' }, { g: 30, label: ':30' }, { g: 15, label: ':15' }].map(({ g, label }) => (
              <Pressable
                key={g}
                onPress={() => changeGranularity(g)}
                style={[styles.granularityChip, granularity === g && styles.slotSelected]}
              >
                <Text style={[styles.slotText, granularity === g && styles.slotTextSelected]}>{label}</Text>
              </Pressable>
            ))}
          </View>
        </View>
```

Change the grid render to use `visibleTimeChips` (both the `.length === 0` empty check and the `.map`). Add to `makeStyles` (next to `slotChip`):

```javascript
  granularityChip: {
    paddingHorizontal: 10,
    paddingVertical: 4,
    borderRadius: borderRadius.md,
    borderWidth: 1,
    borderColor: colors.border,
    backgroundColor: colors.surface,
  },
```

- [ ] **Step 4: Empty-state copy (spec §5)**

The `timeChips.length === 0` branch becomes `visibleTimeChips.length === 0` with friendlier copy:

```jsx
          <Card>
            <Text style={[typography.bodySmall, { textAlign: 'center' }]}>
              {timeChips.length > 0
                ? 'No on-the-hour starts left — try :30 or :15.'
                : selectedDateStr === todayISO
                  ? 'No more bookable times today — try tomorrow.'
                  : 'No bookable times for this date.'}
            </Text>
          </Card>
```

- [ ] **Step 5: Parse-check + jest, commit**

Run: `node -e "const p=require('@babel/parser'); p.parse(require('fs').readFileSync('src/screens/book/ReserveLaterScreen.js','utf8'),{sourceType:'module',plugins:['jsx']}); console.log('ok')"` then `npx jest`
Expected: parses; full suite green.

```bash
git add src/screens/book/ReserveLaterScreen.js
git commit -m "feat: Hour/:30/:15 start-time granularity chips (default Hour)"
```

---

### Task 7: Duration chips 30/60/90/120 (mobile)

**Files:**
- Modify: `src/screens/book/ReserveLaterScreen.js` (~line 409)

- [ ] **Step 1: Change the preset row**

`{[30, 60, 90, 240].map((d) => {` → `{[30, 60, 90, 120].map((d) => {`
(The slider immediately below still covers 15 min–4 h.)

- [ ] **Step 2: Commit**

```bash
git add src/screens/book/ReserveLaterScreen.js
git commit -m "feat: duration presets 30m/1h/1h30/2h (slider still to 4h)"
```

---

### Task 8: "Just missed it" conflict alert + refresh (mobile)

**Files:**
- Modify: `src/screens/book/ReserveLaterScreen.js` — the `handleBook` catch (~lines 314–319)

- [ ] **Step 1: Replace the catch**

```javascript
    } catch (e) {
      Haptics.notificationAsync(Haptics.NotificationFeedbackType.Error);
      const { isConflict, message } = conflictFromError(e);
      if (isConflict) {
        // Someone booked the room between the list loading and this tap.
        // The server sentence names the room + window; the refresh drops the
        // stale room and surfaces alternatives for the same slot.
        Alert.alert('Just missed it', message, [
          { text: 'Cancel', style: 'cancel' },
          { text: 'See updated rooms', onPress: () => showRooms() },
        ]);
      } else {
        Alert.alert(
          isEditing ? 'Update Failed' : 'Booking Failed',
          message || 'Please try again.'
        );
      }
    } finally {
```

- [ ] **Step 2: Jest + commit**

Run: `npx jest` — Expected: green.

```bash
git add src/screens/book/ReserveLaterScreen.js
git commit -m "feat: conflict bookings get 'Just missed it' + one-tap room refresh"
```

---

### Task 9: Confirm button labeling (mobile)

**Files:**
- Modify: `src/screens/book/ReserveLaterScreen.js` — the footer `<Button title={(() => { … })()}` (~lines 650–658)

- [ ] **Step 1: Replace the title IIFE's final two lines**

```javascript
              if (isEditing) return total > 0 ? `Save · $${(total / 100).toFixed(2)}` : 'Save Changes';
              return total > 0 ? `Confirm · $${(total / 100).toFixed(2)}` : 'Confirm Booking';
```

become:

```javascript
              return confirmButtonLabel({
                isEditing,
                roomName: selectedRoom?.name,
                timeLabel: selectedTimeLabel,
                totalCents: total,
              });
```

(`selectedTimeLabel` already exists in the component — it feeds the booking summary string.)

- [ ] **Step 2: Jest + commit**

Run: `npx jest` — Expected: green.

```bash
git add src/screens/book/ReserveLaterScreen.js
git commit -m "feat: confirm button states room + time/price"
```

---

### Task 10: Collapsing calendar (mobile)

**Files:**
- Modify: `src/screens/book/ReserveLaterScreen.js` — DATE section (~lines 325–365), state block

- [ ] **Step 1: State**

```javascript
  // The calendar is a full screen of scroll once a date is picked; collapse
  // it to a one-line date row (tap to reopen).
  const [calendarOpen, setCalendarOpen] = useState(true);
```

- [ ] **Step 2: Wrap the calendar**

The Calendar's `onDayPress` gains `setCalendarOpen(false);` after `setSelectedDateStr(...)`. Wrap the `<Card><Calendar …/></Card>` block:

```jsx
        {calendarOpen ? (
          <Card>
            <Calendar … (unchanged) … />
          </Card>
        ) : (
          <Pressable onPress={() => setCalendarOpen(true)}>
            <Card>
              <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' }}>
                <Text style={typography.body}>{formatDateLabel(selectedDate)}</Text>
                <Text style={[typography.bodySmall, { color: colors.primary }]}>Change ▾</Text>
              </View>
            </Card>
          </Pressable>
        )}
```

(`formatDateLabel` and `selectedDate` already exist — they feed the booking summary.)

- [ ] **Step 3: Parse-check + jest + commit**

Run: parse-check command from Task 6, then `npx jest`. Expected: green.

```bash
git add src/screens/book/ReserveLaterScreen.js
git commit -m "feat: calendar collapses to a date row after picking"
```

---

### Task 11: Ship

- [ ] **Step 1: Full suites one last time**

Backend worktree: `PATH="$HOME/.rbenv/shims:$PATH" PARALLEL_WORKERS=1 bin/rails test test/models/reservation_window_label_test.rb test/validators/ test/controllers/api/v1/reservations_conflict_test.rb test/controllers/api/v1/reservations_controller_test.rb`
Mobile: `npx jest`
Expected: all green.

- [ ] **Step 2: Mobile PR**

```bash
git push -u origin feature/reserve-later-refinement
gh pr create --title "Reserve Later: granularity chips, honest conflicts, polish" \
  --body "Mobile half of the approved spec (new-jellyswitch docs/superpowers/specs/2026-07-02-reserve-later-refinement-design.md). Pairs with the backend 409 PR; fully backward-compatible in both directions (non-409 errors keep today's alert; old bundles get the improved server sentence raw)."
```

- [ ] **Step 3: After CI green on the backend PR** — merge backend first (auto-deploys), then mobile, then OTA all four brands:

```bash
for b in untethered cowork-tahoe choose-folsom tahoelonghouse; do
  BRAND=$b npx eas update --channel production --non-interactive \
    --message "reserve later: granularity chips, honest conflicts, polish"
done
```

---

## Self-review notes

- Spec coverage: §1 granularity → Tasks 5–6; §2 duration → Task 7; §3 rooms available-only → no change needed (confirmed intentional); §4 conflicts → Tasks 1–4, 5, 8; §5 polish → Tasks 6 (empty state), 9, 10; testing → embedded per task. No gaps.
- Backward compatibility: old bundles render the improved `error` sentence raw (Task 2's message is member-facing); new bundle + old backend degrades to the generic alert (409 never arrives → `isConflict` false).
- Type consistency: `conflictFromError` shape `{isConflict, message}` matches Task 8's destructure; `confirmButtonLabel` args match Task 9's call; `filterTimesByGranularity(times, g)` matches Tasks 5/6.
