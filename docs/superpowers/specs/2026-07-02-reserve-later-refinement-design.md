# Reserve Later Refinement — Design

**Date:** 2026-07-02 · **Status:** approved by David (brainstorm session)
**Repos:** jellyswitch-mobile (primary) + new-jellyswitch (conflict error)

## Why

Operator feedback on mobile meeting-room booking:

1. Booking a room that was (partially) reserved across the requested window
   produced a generic "Booking Failed" with no indication the room was taken
   or when. (The "rooms appear before time" half of the report predates the
   when-first flow, which already ships Date → Time → Duration → Rooms.)
2. The 15-minute time grid is a wall of ~40 chips. David wants slot-
   granularity chips — 15/30/60 — with **60 as the default** so the grid
   opens as top-of-the-hour starts.
3. General "convenient and easy" polish.

Decisions made during the session:

- **Available rooms only.** Rooms not bookable for the requested window are
  dropped entirely — no greyed rows, no "free at" hints, no availability
  bars. (Considered and rejected: per-room day timelines, tappable mini
  availability bars.)
- The granularity chips control **start-time density**, not duration.

## 1 · Time granularity toggle (mobile only)

- TIME section header gets a right-aligned three-chip toggle: **Hour · :30 ·
  :15**. Default **Hour**.
- Pure client-side filter over the existing `/rooms/booking_times` 15-min
  grid: Hour → minutes == 0; :30 → 0/30; :15 → all. No backend change.
- Selected time is preserved across granularity switches when it remains in
  the filtered grid; otherwise selection clears (rooms list resets with it).
- Today's past-time trimming and role-gated hour bounds are unchanged (they
  live server-side).
- Not persisted per-user in V1; screen always opens on Hour.

## 2 · Duration row (light touch, mobile only)

- Chips become **30m / 1h / 1h 30m / 2h** (replacing 30/60/90/**4h** — the
  4h chip was a dead jump). The 15-min slider stays for anything else, max
  4h. Default remains `user.preferred_meeting_duration` (fallback 60).

## 3 · Rooms list

- Unchanged contract: render `available_rooms` only. The API's
  `unavailable_rooms` payload stays available for web/other clients but
  mobile intentionally ignores it (explicit product decision, this session).

## 4 · Honest conflict handling (the bug fix)

**Backend (new-jellyswitch):**

- When `reservations#create` / `#update` rejects for a room-time overlap,
  return HTTP 409 with a structured body:

  ```json
  {
    "error": "Meeting Room 3B is no longer free 10:00–11:00 AM.",
    "conflict": { "room_name": "Meeting Room 3B",
                  "window_label": "10:00–11:00 AM" }
  }
  ```

- `error` is the human sentence (older app bundles that render
  `e.response.data.error` raw get the good message for free — that alone
  fixes the field complaint). `conflict` lets new bundles style the alert.
- The window in the message is the REQUESTED window in the location's zone.

**Mobile:**

- On 409-with-`conflict`, show a **"Just missed it"** alert: the server
  sentence + a **"See updated rooms"** button that re-runs the availability
  fetch for the current date/time/duration (stale room drops out,
  alternatives are right there). Cancel stays on screen.
- Non-conflict errors keep today's generic alert.
- Applies to create and edit paths (both live in ReserveLaterScreen).

## 5 · Polish (mobile)

- Confirm button states the action: **"Reserve Room 3B · 10–11 AM"**
  (falls back to "Reserve Room" pre-selection).
- After a date is picked, the calendar collapses to a compact date row
  ("Tue, Jul 7 ▾"); tapping reopens it. Cuts a full screen of scroll.
- Consistent section spacing; friendlier empty state for "no bookable
  times".

## Testing

- Jest: granularity filter (Hour/:30/:15 over a sample grid, past-trim
  interplay, selection preservation), conflict-alert branch (409 w/ and
  w/o `conflict`), confirm-button label.
- Minitest: overlap rejection returns 409 + `error` sentence + `conflict`
  object, in location-local time; non-overlap errors unchanged.
- Existing reserve-later tests updated for the new chip defaults.

## Out of scope

- Reserve Now screen (separate slider flow) — untouched.
- Web reserve flow — already constrains to available times.
- Per-user granularity persistence; per-room day timelines (rejected).
