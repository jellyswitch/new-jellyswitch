# A reservation grants a time-bounded access window, not all-day, and no comp pass

A **Reservation** grants the booker building access **only inside an Access window** around its slot: from `Operator.building_access_window_minutes` before start to the same number of minutes after end (default 60). Outside that window the reservation grants no access. A booker who has only a paid **Meeting room** reservation (no Day Pass, membership, or lease) gets building access **solely** from this window. Day Pass, membership, lease, and bundle access are unchanged.

## Context

`user_can_access_building?` granted building access for **any** non-cancelled reservation that day, with no time bound — booking a 3pm room let you in at midnight. Separately, paid-room bookings minted a complimentary Day Pass (`GrantFreeDayPass`), which both gave free all-day access and poisoned edit re-pricing (ADR 0012). Removing the comp pass (ADR 0012) would strand paid-room bookers with **no** way in — so the access window must ship together with that removal.

## Decision

Replace the all-day reservation clause with a precise window check (`Reservation#access_window_open?`, computed zone-correctly from the location time zone). The window length is an operator setting. The door-unlock candidate query widens by ±(1 day + window) to catch midnight spillover, with the exact in/out decision made in Ruby. The "come back ~1hr before to get in" push (ADR-adjacent, Phase 6) reads the **same** operator column so the promise can never drift from the door.

## Consequences

- **One additive operator column** (`building_access_window_minutes`); door and notification read the same value.
- Members/leaseholders are unaffected — their access comes from membership/lease, not the reservation.
- Paid-room-only bookers now get a *window*, not a day — which is the intended separation of "buy a room" from "buy a day."
- Ships in the same release as the comp-pass removal (ADR 0012) so no booker is ever locked out.
