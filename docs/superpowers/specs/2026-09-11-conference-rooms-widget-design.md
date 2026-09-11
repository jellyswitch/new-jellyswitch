# Conference Rooms website widget — design (2026-09-11)

**Ask (David):** "Conference room widget! We forgot one of our products! We need the ability to show nice pictures, list of amenities and a book now button."

## Shape
A fifth script-embed widget, a sibling of Office Inventory (ADR 0027 inline DOM):
`GET /embed/rooms/:operator_subdomain[?location_id=]` → `Embed::RoomsController#widget` → `rooms/widget.js.erb` (`.jsw-rm` classes). 1-minute public cache; settings-page preview token shows it while disabled; multi-location operators get the same "pin a location" nudge as the Showcase.

## Card
Photo (the room's existing single `photo`), name, "Seats N · N sqft", rate ("$50/hr"; a $0 room says "Included with a day pass" or "Included with membership"), description, check-mark list = `Room#website_bullets` (typed `features` + free amenity names — the same two lists the app shows), **Book now** → `https://<subdomain>.<HOST>/reservations/choose_day?room_id=<id>` (login gate stores `return_to`, so a new visitor signs up and lands back in the wizard).

## Which rooms
`visible.rentable` at the location, ordered by capacity then name. Rentable = the room form's "available to rent for non-members" box — the rooms a website visitor can pay for. (David may widen to all visible rooms later.)

## Settings
`operators.conference_rooms_enabled` (default false). Website Widgets picker gains a "Conference Rooms" pill (`WIDGETS` key `rooms`, partial `_rooms`): enable checkbox, live srcdoc preview, per-location snippets. The web room form gains a "Features — one per line" box writing `features` (the mobile admin API already edits that column).

## Not built (on purpose)
Multi-photo gallery per room (new upload UI), JSON-LD markup, a booking/inquiry form inside the widget.
