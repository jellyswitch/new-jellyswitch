# Interest is stored tags, behavior-defaulted and staff-adjustable — not derived like Lifecycle Stage

A Person's **Interest** (office / day pass / membership / meeting room) is a set of **stored tags** on the User. A default tag is **computed from behavior** — the Person's last purchased product if they've bought anything, otherwise what they last looked at (concierge intent, browsing, checkout attempts) — and written to storage. Staff can then **add, remove, or adjust** tags, and those staff edits are **sticky** (a later behavioral signal does not clobber a staff-set tag). Campaigns and lists target by Interest tag.

This deliberately **does not** follow ADR 0002 (Lifecycle Stage is derived at query time, never stored).

## Context

ADR 0002 established a strong local convention: don't store a denormalization that drifts — Lifecycle Stage is derived on read from subscription state and activity. The temptation is to make Interest derived the same way: query "what products has this Person shown intent in" from the Activity table at read time.

But Interest has two properties Lifecycle Stage does not:

1. **Staff annotations are not derivable.** A staff member learns on a phone call that someone wants an office — there is no behavioral event to derive that from. It is an explicit fact the operator asserts. It must be stored somewhere, and it must survive the person's later browsing.
2. **The highest-value population has no behavior to derive from.** The whole point of Interest is to make **New signups** targetable — people who have not purchased and may have barely browsed. A pure derivation returns nothing for them; a stored tag (even one seeded by a single concierge message or a staff note) gives the operator something to act on.

Interest is also a **stable operator worklist** (the "office waitlist"): the operator wants a durable list they can order, export, cull, and add people to by hand — not a query result that silently reshuffles as behavior changes underneath them.

## Considered Options

- **(a) Pure-derived, like Lifecycle Stage.** Interest = query over Activities at read time. Consistent with ADR 0002, nothing to drift. But it cannot hold staff annotations, returns empty for New signups with no logged behavior, and gives the operator no stable list to add-to / cull / export.
- **(b) Stored tags, behavior-defaulted, staff-adjustable (chosen).** A tag row per (User, product). A behavioral default is computed and written; staff add/remove/adjust; staff edits win over later behavior.
- **(c) Hybrid: derived behavioral set UNION stored staff annotations.** Behavioral part stays a live query; only staff tags are stored; the two union at read time. Honors ADR 0002 for the behavioral half, but the "add a person to the list / cull the list / export a stable list" operations straddle a query and a table, the ordering (members-by-signup-date, then outside parties) has to be applied to a moving set, and there is no single place to answer "is this person on the office list?".

## Why (b)

1. **Staff edits are first-class, and they must persist.** Offline conversations are a primary interest source ("called, wants an office"). A stored, staff-editable tag is the only shape where "add / remove / adjust / add-a-person-manually" are ordinary CRUD, not special-cased writes into a derivation.
2. **New signups become reachable.** Seeding a tag from a single signal (or a staff note) means the inbound population the operator most wants — people who just showed up interested — actually appear on a list.
3. **The operator wants a durable worklist, not a query.** Ordering, export, per-list suppression, and manual additions all assume a stable set of rows. A moving query fights every one of those.
4. **The drift is bounded and cheap to manage.** The only derived input is the *default* tag, refreshed on the few events that change it (a purchase, a concierge intent). It is not the rolling, time-of-day-sensitive derivation ADR 0002 was avoiding (Lifecycle Stage's "Quiet" flips at midnight); an interest default only moves when the Person does something.

## Consequences

- **A new stored shape** — an interest-tag row per (User, product), carrying its **source** (behavioral vs staff) so a behavioral refresh never overwrites a staff-set tag.
- **ADR 0002 still holds for Lifecycle Stage.** These are different concepts: Stage is *where* a Person is (derived); Interest is *what* they want (stored). Do not "fix" Interest to be derived to match Stage — re-read this ADR first.
- **The behavioral default needs write hooks** on the events that set it (purchase, concierge intent), plus a backfill for existing users (default = last purchased product). Absent any signal, a Person simply has no interest tag until staff add one — acceptable; they still appear in the Cold-signup list.
- **Lists are stable and operable.** "The office waitlist" is `People WHERE interest tag = office`, ordered members-first-by-signup-date then outside parties — a real, exportable, cullable, hand-editable list, not a reshuffling query.
