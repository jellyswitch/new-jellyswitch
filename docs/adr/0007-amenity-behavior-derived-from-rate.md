# Amenity behavior is derived from its rate, not a stored type

An `Amenity` attached to a Room is either a passive **room feature** (a whiteboard, a monitor) or an **orderable add-on** (catering). That distinction is **derived from the amenity's two rates**, not stored as a `type`/`kind` column:

- **Both rates `0`** → a **room feature**: shown as an informational chip, never selectable, never creates an `amenities_reservations` row, never charged.
- **Any rate `> 0`** (`max(price, membership_price) > 0`) → an **orderable add-on**: selectable per Reservation, creates the join row, and is charged at the booker's applicable rate (member vs non-member — see CONTEXT.md → Amenity).

## Considered Options

- **Derived from rate (chosen).** One `amenities` table; `price` (non-member) + `membership_price` (member) already exist. Behavior falls out of whether either rate is non-zero.
- **Stored type column.** Add `amenities.kind` (`feature` | `add_on`), set by the admin form, validated against the rates.
- **Two tables.** Split into `room_features` (name only) and `room_add_ons` (name + two rates), each with its own model, form, and API shape.

## Why derived

1. **The rate already says it.** A free thing isn't ordered and isn't charged; a priced thing is. A `kind` column would just be a denormalization of "is either rate > 0?" — and denormalizations drift (a `feature` row with a non-zero price, or an `add_on` priced at 0/0, would be nonsense the validations have to police).
2. **No schema change, no data migration.** The existing `amenities` rows and the `price` / `membership_price` columns carry the whole model. Existing web bookings keep working unchanged.
3. **One admin surface.** The room form shows every amenity with two rate fields defaulting to `0`. "List what the room has" is the easy path (leave rates blank → feature); pricing is opt-in (type a rate → add-on). No mode toggle, no type picker. (This replaces the old "Regular/Membership" radio, which only showed one rate at a time and misrepresented pricing as an either/or mode.)
4. **Consistent with the codebase.** Same pattern as `0002-lifecycle-stage-derived` and `0004-day-pool-gates-access-not-membership`: behavior is read from the data that already implies it rather than a parallel stored flag.

## Consequences

- **Don't add an `amenities.kind` column.** The temptation will be there when building the form/API; resist it. Selectability is computed: `max(price, membership_price) > 0`.
- **There is no "free but must request" amenity.** A 0/0 amenity is always a non-selectable feature. If a future operator genuinely needs a free-but-orderable item, that's a model change to revisit here — not a workaround (e.g. don't price it at $0.01).
- **The mobile API splits by the same rule.** The room payload exposes `features` (names only) and `add_ons` (id + both rates in cents); the app renders features as chips and add-ons as selectable rows. The booking POST sends only `amenity_ids`; the server recomputes the charge from those IDs and the booker's membership status — the client never sends a price.
- **Flipping an amenity between feature and add-on is just editing its rate.** Setting catering back to 0/0 makes it a feature again; no migration, no record-type change.
