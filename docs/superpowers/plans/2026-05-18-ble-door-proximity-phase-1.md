# BLE Door Proximity (Auto-Unlock) Phase 1 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship "walk up and the door unlocks" UX for members. iOS + Android, opt-in toggle default OFF, beacon-based via BlueCharm BC04P, sits on top of existing Kisi unlock flow.

**Architecture:** [docs/superpowers/specs/2026-05-18-ble-door-proximity-phase-1-design.md](../specs/2026-05-18-ble-door-proximity-phase-1-design.md)

**Spec:** ditto

**Estimated elapsed:** 2-3 weeks (5-10 work days excluding RSSI calibration week)

---

## Phase 1.0 — Hardware order + Kisi inquiry (~30 min, today)

- [ ] Order [BC04P 3-pack on Amazon](https://www.amazon.com/Blue-Charm-Beacons-Water-Resistant-BC04P-MultiBeacon/dp/B0G4XXK7LL) (~$85). Delivered to Tahoe in 2 days.
- [ ] Email Kisi support: "Do Reader Pro / Reader Touch broadcast a stable iBeacon-format BLE UUID we can listen to, or does our app need to host its own beacons?" — answer determines whether we put beacons at every door or just non-Kisi areas.

## Phase 1.1 — Rails: data model + auto_unlock endpoint (~1 day)

- [ ] Migration: `Beacon` table (`uuid, major, minor, location_id, door_id?, name, last_seen_at?, battery_percent?, installed_at, active`)
- [ ] Migration: add `source` column to `DoorPunch` (enum `manual` / `auto_unlock`, default `manual`)
- [ ] Model `Beacon` with `belongs_to :location, :door (optional)`, scopes `.active`, `.stale (last_seen > 7d ago)`, `.low_battery (<15%)`
- [ ] Model spec coverage: beacon lookup by uuid+major+minor, scope correctness
- [ ] Controller `Api::V1::DoorsController#auto_unlock` — accepts `{beacon_uuid, beacon_major, beacon_minor, nonce, rssi}`
- [ ] Service `Doors::AutoUnlock` — orchestrates the membership check + nonce dedup + Kisi call + DoorPunch creation
- [ ] Nonce dedup via Redis `SETEX` (60s TTL), reject if key already exists
- [ ] RSSI threshold check (`Beacon.rssi_threshold_dbm`, default -65, configurable per-beacon)
- [ ] Service spec: happy path, membership_inactive, nonce_replay, rssi_too_weak, kisi_failure
- [ ] Controller request spec: auth required, payload validation, error response shapes
- [ ] Routes: `POST /api/v1/door/auto_unlock`

## Phase 1.2 — Rails: telemetry + admin UI (~0.5 day)

- [ ] Controller `Api::V1::BeaconHealthController#create` — accepts `{beacon_uuid, beacon_major, beacon_minor, battery_percent, rssi}`, updates `Beacon.last_seen_at` + `battery_percent`
- [ ] Routes: `POST /api/v1/beacon_health`
- [ ] Admin UI: `Operator::Settings::BeaconsController` (index, create, update, destroy)
- [ ] View: `operator/settings/beacons/index.html.erb` — table per location with name, battery%, last_seen, threshold (editable), actions (edit, retire)
- [ ] Add `Beacons` link to the Operator → Settings nav
- [ ] Actionable Insight: surface stale beacons (last_seen > 7d) + low-battery beacons (<15%) in the dashboard "Action Needed" feed
- [ ] Tests: controller request spec, view smoke spec, insight presence

## Phase 1.3 — Mobile (iOS): scanning + auto_unlock call (~2-3 days)

- [ ] Update `Info.plist` strings via `app.config.js`:
  - `NSLocationAlwaysAndWhenInUseUsageDescription` → "Detect when you arrive at a Jellyswitch location to auto-unlock doors. We never share location off-device."
  - `NSBluetoothAlwaysUsageDescription` → "Detect door beacons so the app can unlock doors without you taking your phone out."
- [ ] New module `src/services/AutoUnlockService.js` — wraps `react-native-beacons-manager` or equivalent for iBeacon ranging
- [ ] iOS region monitoring start/stop on app-launch + foreground/background transitions
- [ ] On region-enter: range briefly, find closest beacon, if RSSI > threshold → call `POST /api/v1/door/auto_unlock`
- [ ] Nonce generation via `expo-crypto.randomBytes(16).toString('base64')`
- [ ] Phone-state check: `expo-local-authentication` recent auth or skip
- [ ] On success: schedule local notification "{Door name} unlocked"
- [ ] On failure: silent (don't badge the user with red errors for things they can't act on)
- [ ] Background telemetry: every 24h while ranging, POST battery_percent from Eddystone TLM

## Phase 1.4 — Mobile (Android): scanning + auto_unlock call (~2-3 days)

- [ ] `react-native-permissions` for `BLUETOOTH_SCAN` + `BLUETOOTH_CONNECT` (Android 12+) + `ACCESS_FINE_LOCATION`
- [ ] Foreground service for continuous scan (extend existing `expo-task-manager` setup or write a native module)
- [ ] Notification channel "Auto-Unlock Service" (low importance, no sound) — required for foreground service
- [ ] Same scan-result → auto_unlock call flow as iOS
- [ ] Phone-state check via `KeyguardManager.isKeyguardLocked`

## Phase 1.5 — Mobile: opt-in toggle + onboarding (~1 day)

- [ ] Settings screen: new "Auto-Unlock" row, default OFF
- [ ] On toggle ON: walk through permission asks in sequence (location → bluetooth → done)
- [ ] On toggle OFF: stop region monitoring + foreground service immediately
- [ ] First-success modal: "Auto-Unlock is on. You can disable it anytime in Settings."
- [ ] Settings sub-row: "Show notification when door unlocks" (default ON)
- [ ] Settings sub-row: "Auto-unlock even when phone is locked" (default OFF, with security warning copy)

## Phase 1.6 — RSSI calibration week (field testing, 5+ days elapsed)

- [ ] Dev-mode admin screen: "Beacon calibration" — live RSSI graph during ranging
- [ ] Install BC04P at Untethered front door
- [ ] Walk repeatedly from 0.5m, 1m, 2m, 3m, 5m, 10m. Log to admin dev screen.
- [ ] Pick `rssi_threshold_dbm` per beacon that triggers reliably at ~1.5m and never at >5m
- [ ] Persist per-beacon threshold via admin UI
- [ ] Repeat for ~3 doors per location to gauge how much per-door variance exists
- [ ] Document RSSI thresholds + their distance equivalents in memory for future installs

## Phase 1.7 — Production rollout (~1 day per location)

- [ ] Internal beta: enable Auto-Unlock for self only at Untethered Tahoe, run for 1 week
- [ ] Bug bash: anything that surprises us (door unlocks while user is *leaving*, double-fires, etc.)
- [ ] Open to all Untethered Tahoe members with an in-app announcement
- [ ] Phase to Cowork Tahoe (likely needs more beacons + UWB Phase 2 evaluation)
- [ ] Phase to Choose Folsom

---

## File map (Rails)

**New files:**
- `db/migrate/<ts>_create_beacons.rb`
- `db/migrate/<ts>_add_source_to_door_punches.rb`
- `app/models/beacon.rb`
- `app/controllers/api/v1/doors_controller.rb` (or new action in existing controller)
- `app/controllers/api/v1/beacon_health_controller.rb`
- `app/controllers/operator/settings/beacons_controller.rb`
- `app/services/doors/auto_unlock.rb`
- `app/views/operator/settings/beacons/index.html.erb`
- `app/views/operator/settings/beacons/_form.html.erb`
- `test/models/beacon_test.rb`
- `test/services/doors/auto_unlock_test.rb`
- `test/controllers/api/v1/doors_controller_test.rb`
- `test/controllers/api/v1/beacon_health_controller_test.rb`
- `test/controllers/operator/settings/beacons_controller_test.rb`

**Modified files:**
- `app/models/door_punch.rb` (add `source` enum)
- `app/models/location.rb` (`has_many :beacons`)
- `config/routes.rb` (api routes + admin routes)
- `lib/jellyswitch/report.rb` (add stale-beacon + low-battery to `actionable_insights`)
- `app/views/operator/settings/_nav.html.erb` (add "Beacons" link)

## File map (Mobile)

**New files:**
- `src/services/AutoUnlockService.js`
- `src/services/BeaconScanner.ios.js`
- `src/services/BeaconScanner.android.js`
- `src/screens/settings/AutoUnlockSettingsScreen.js`
- `src/screens/admin/BeaconCalibrationScreen.js` (dev mode)

**Modified files:**
- `app.config.js` (Info.plist strings + Android permissions + foreground-service config)
- `package.json` (add `react-native-beacons-manager` or chosen lib)
- `src/screens/account/SettingsScreen.js` (add Auto-Unlock row)
- `src/api/client.js` (add `doorsAPI.autoUnlock`, `beaconHealthAPI.heartbeat`)
- `src/navigation/AppNavigator.js` (register AutoUnlockSettingsScreen + BeaconCalibrationScreen)

## Risks / open questions

- **Kisi BLE response** decides whether we deploy beacons at all Kisi-gated doors or skip them
- **Apple "Always Allow" permission acceptance rate** is unknown; bake in good messaging
- **Android battery cost** of foreground service may push us to a "scan window" approach (only scan during likely-arrival hours per user's check-in history)
- **`react-native-beacons-manager` maintenance status** — verify it still works on RN 0.81 + iOS 18 / iOS 26; fallback is native iOS module via Expo config plugin
- **Kisi unlock latency** — if >2s, the "door unlocks before I reach it" UX falls apart; may need to start the unlock at ~2m not 1.5m to compensate
