# BLE Door Proximity (Auto-Unlock) — Phase 1 Design

**Status:** Draft, 2026-05-18
**Related:** [Phase 1 Plan](../plans/2026-05-18-ble-door-proximity-phase-1.md), [Memory: BLE decision](../../../../.claude/projects/-Users-DavidOrr-Downloads-new-jellyswitch/memory/project_ble_door_proximity_2026_05_18.md), [Memory: UWB Phase 2](../../../../.claude/projects/-Users-DavidOrr-Downloads-new-jellyswitch/memory/project_uwb_door_proximity.md)

## Problem

> "One of the big pain points of the app is having to pull your phone out of your pocket, find the app, and open the doors." — DR

Today: member arrives at door → unlocks phone → opens Untethered/CT/CF app → taps unlock → DoorPunch created via Kisi API. ~10-15 seconds of friction every time, every member, every day.

Goal: member approaches door with the phone in their pocket → door unlocks automatically before they reach it. Eliminate the explicit "open app + tap" step. Pattern matches Tesla Phone Key, Marriott Bonvoy, Hilton Honors door unlock.

## Non-goals (Phase 1)

- **UWB precision / directional unlock.** Defer to Phase 2 — needed only where multiple doors are within ~3m of each other (likely a Cowork Tahoe problem, not Untethered).
- **Hands-free unlock when phone is locked.** Phase 1 requires phone unlocked OR recently used (LAContext/keychain access) — defense-in-depth against stolen-phone abuse.
- **Apple Watch unlock.** Out of scope for Phase 1.
- **Replacing Kisi.** This sits on top of Kisi; Kisi still owns the relay.

## Architecture

```
Member's phone (BLE scan in background)
    │
    │  iBeacon UUID detected via CoreLocation region monitoring
    │  (iOS) or BluetoothLeScanner foreground service (Android)
    ▼
Mobile app wakes (~10s window on iOS)
    │
    │  POST /api/v1/door/auto_unlock
    │  { beacon_uuid, beacon_major, beacon_minor, nonce, rssi }
    ▼
Rails Api::V1::DoorsController#auto_unlock
    │  1. Lookup Beacon by (uuid, major, minor) → location, door_id
    │  2. Verify user has active membership at location
    │  3. Verify rssi within unlock threshold (anti-replay-from-distance)
    │  4. Verify nonce hasn't been seen in last 60s (anti-replay)
    │  5. Call Kisi unlock API for door_id
    │  6. Create DoorPunch(user, door, source: :auto_unlock)
    │  7. Return 200 + door_name for the "Door unlocked" notification
    ▼
Mobile shows local notification: "Untethered front door unlocked"
```

## Hardware

**Beacon:** BlueCharm BC04P-MultiBeacon — see decision memory. IP67, BT5 PHY-coded, CR2477 4yr battery, $30/ea.

**Placement:** Door frame, interior side, ~5-7 ft up. Test RSSI from 0.5m / 2m / 5m / 10m at each door — final placement adjusts to put the auto-unlock trigger at ~1.5-2m (typical "I'm about to enter" distance).

**Provisioning:** Each beacon is configured via BlueCharm's iPhone app to broadcast a stable iBeacon UUID + per-door major.minor pair. UUID is operator-wide (1 per operator); major = location_id, minor = door_id. Configured once at install, never changes.

## Data model (Rails)

```ruby
class Beacon < ApplicationRecord
  # Schema:
  #   uuid             :string  not null   # iBeacon UUID, operator-wide
  #   major            :integer not null   # = location_id
  #   minor            :integer not null   # = door_id (or arbitrary stable int)
  #   location_id      :integer not null
  #   door_id          :integer            # null if beacon isn't tied to a Kisi door (e.g., zone-only)
  #   name             :string             # admin display name, e.g. "Front door"
  #   last_seen_at     :datetime           # heartbeat from mobile telemetry
  #   battery_percent  :integer            # from Eddystone TLM, 0-100
  #   installed_at     :datetime
  #   active           :boolean default: true
  #
  # Indexes:
  #   [uuid, major, minor] (unique)
  #   [location_id]
  belongs_to :location
  belongs_to :door, optional: true
  has_many   :door_punches  # via source: :auto_unlock
end
```

```ruby
class DoorPunch < ApplicationRecord
  # add column:
  #   source :string  # one of: 'manual', 'auto_unlock'
  enum :source, { manual: 'manual', auto_unlock: 'auto_unlock' }
end
```

## API

`POST /api/v1/door/auto_unlock` (authenticated, JSON):

```json
Request:
{
  "beacon_uuid": "...",
  "beacon_major": 12,
  "beacon_minor": 3,
  "nonce": "<128-bit base64>",
  "rssi": -62
}

Response (success):
{
  "unlocked": true,
  "door_name": "Untethered Front Door",
  "auto_relock_seconds": 5
}

Response (failure):
{
  "unlocked": false,
  "reason": "membership_inactive" | "rssi_too_weak" | "nonce_replay" | "kisi_failure" | "out_of_hours"
}
```

**Auth:** existing JWT (no new token type).
**Rate limit:** 1 unlock per (user, beacon) per 30s.
**Failure modes are logged but don't surface as user-facing errors** — auto-unlock silently noops if it can't fire (member can still tap manually).

## Mobile architecture

### iOS

- **`CLLocationManager.startMonitoring(for: CLBeaconRegion)`** for the operator's iBeacon UUID. Triggers background wake on enter/exit region.
- **`CLLocationManager.startRangingBeacons`** *only* when foregrounded or briefly during the wake-up window — ranging is power-expensive and Apple restricts it in background.
- Requires `NSLocationAlwaysAndWhenInUseUsageDescription` (already in app.config.js for "Help us suggest the closest location and remember where you're from" — wording update needed).
- Background wake gives ~10 seconds of execution time. Plenty for one API call.

### Android

- **`BluetoothLeScanner`** with a `ScanFilter` for the beacon UUID. Foreground service required for continuous scanning (Android 8+).
- Notification "Auto-unlock active" persistent in the notification shade while service runs.
- Higher battery cost than iOS — let user disable from settings (and remind on a power-save mode wake).

### Shared

- **`AutoUnlockService`** module reads opt-in toggle from user prefs. No-op if off.
- **Nonce generation:** `expo-crypto.randomBytes(16)`, base64-encoded.
- **Phone-unlocked check:** iOS via `LAContext.evaluateAccessControl(... .userPresence)` polling, Android via `KeyguardManager.isKeyguardLocked` — bail if locked unless user opted into "auto-unlock even when locked" (off by default).
- **Notification:** local push "Front door unlocked" with the door name from API response.

## User-facing UX

1. **Settings → Auto-Unlock toggle** (default OFF).
2. On toggle ON: walk through:
   - "We need always-on location to detect when you're at your space" → Apple permission ask
   - "We need Bluetooth to detect the door beacons" → Bluetooth permission
   - "Auto-unlock will only fire when your phone is unlocked / recently used" — phone-state setting explanation
3. On first successful auto-unlock: a one-time onboarding notification "Tip: you can disable this anytime in Settings → Auto-Unlock."
4. Every auto-unlock fires a local notification (audible toggle in settings).

## Security model

| Threat | Mitigation |
|---|---|
| Beacon UUID cloned + replayed elsewhere | Server checks user is physically at a location with that beacon's geofence (existing API has location detection); RSSI threshold rejects "I see the beacon from across the street" |
| Recorded BLE traffic replayed | Per-request nonce; server tracks last-60s nonces |
| Stolen phone walks into building | Phone-must-be-unlocked-or-recent guard; failed Face ID → no scan |
| Member at home auto-unlocks the door | RSSI threshold > -70 dBm (close enough to require actual physical proximity); plus geofence check |
| Beacon battery dies, member can't unlock | Manual unlock still works (existing flow unchanged); admin gets battery-low alert from telemetry |
| Apple/Google rejection of app for "always location" | Opt-in toggle (off by default); clear permission ask copy; only request when user opts in |

## RSSI calibration

Per-beacon, expect 1-2 hours of tuning. Approach:
- Mount beacon
- Walk repeatedly from 0.5m, 1m, 2m, 3m, 5m with phone in pocket
- Log RSSI samples per distance (admin dev mode in app)
- Pick threshold that fires reliably at 1.5-2m and never at 5m+
- Persist threshold in `Beacon.rssi_threshold_dbm` (default -65, override per-beacon)

## Telemetry & ops

- Mobile reads BC04P's Eddystone TLM frame during normal scanning → POSTs `{beacon_uuid, battery_percent, rssi}` to `/api/v1/beacon_health` every ~24 hr per beacon.
- Rails updates `Beacon.last_seen_at` + `battery_percent`.
- Admin UI under Operator → Settings → Beacons: list of beacons per location with battery%, last-seen, action buttons (rename, retire).
- Alert: if any beacon's `last_seen_at` > 7 days OR `battery_percent` < 15%, surface in admin "Action Needed" feed.

## Out of scope (Phase 1)

- Kisi-side BLE listening (skip if Kisi already broadcasts — confirm with their support first; if so, we don't need BC04P for Kisi-gated doors and beacons stay for non-Kisi areas like meeting rooms / lounge)
- UWB-based direction-finding (Phase 2)
- Apple Watch unlock
- Auto-unlock while phone is locked (configurable opt-in; off by default)
- Multi-tenant beacon sharing (each operator gets a unique UUID)
- Family/guest tap-in unlock (still uses existing manual flow)

## Open questions for the user

1. **Kisi BLE.** Email their support first — does Reader Pro / Touch already broadcast a usable BLE UUID? If yes, no BC04P needed at Kisi doors. (If no, beacons everywhere.)
2. **Should auto-unlock require an active reservation/checkin, or any active membership?** Phase 1 assumes "any active membership" — same as today's manual unlock.
3. **Outside-business-hours auto-unlock allowed?** Phase 1 assumes yes (member can come in anytime).
4. **Notification verbosity.** "Front door unlocked" every time, or only first time per session?

## Phase 2 hooks (don't build, but design with these in mind)

- `Beacon.type` enum (`:ble_ibeacon`, `:uwb_estimote`) so we can extend the schema later
- `Beacon.direction_capable :boolean` so UI knows whether to display directional UX
- The `/api/v1/door/auto_unlock` payload accepts an optional `distance_m` field that UWB will fill in but BLE leaves null
