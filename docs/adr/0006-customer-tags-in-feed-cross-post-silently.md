# Tagging a customer in the team Feed cross-posts to their record, silently

## Context

The team Feed supports `@`-mentions, and the mentionable list includes both staff and approved members. Until now a mention only fired a "X mentioned you" push to whoever was tagged — so an internal note discussing a customer (e.g. "great chat with @Jane, considering upgrading") both (a) **pushed the customer** a notification about an internal note, and (b) left **no trace on the customer's CRM record**. Operators wanted the opposite: tagging a customer should land the note under that customer, and never notify them.

## Decision

The same `@` gesture behaves differently by the tagged user's role:

- **Mention (staff)** — role in `User::STAFF_ROLES` → send the existing "X mentioned you" push. Unchanged.
- **Customer Tag (member)** — any other mentionable user → create a real `Note` on that member (full text, authored by the tagger, with a polymorphic `source` back to the Feed item for provenance) and send **no push**. The member never sees it (CRM notes are admin-facing) and is never notified.

Applies to Feed **posts and comments**. The cross-posted note is a **snapshot**: editing or deleting the source Feed item does not change it (CRM history is immutable; mis-tags are removed via the existing delete-note action). Feed items have no edit endpoint, so each post/comment resolves its tags exactly once at creation — no dedup/re-fire concern.

## Consequences

- Closes a real privacy/UX bug: customers no longer get pushed about internal notes that merely mention them.
- "Discount/upsell chatter" in the team feed now accrues onto the client's record automatically, which is the point.
- A new nullable polymorphic `source` on `notes` distinguishes feed-mirrored notes from hand-written ones and links back to the origin.
