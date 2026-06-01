# Org out_of_band / Stripe `send_invoice` audit — 2026-06-01

Snapshot of every active org subscription whose **Stripe-side** `billing` field is `send_invoice`. Collected via `Stripe::Subscription.retrieve` against prod, scoped to `Subscription.active.where(subscribable_type: "Organization")`.

This is the population at risk from the `out_of_band` → Stripe-collection-method drift bug fixed in branch `claude/org-out-of-band-stripe-sync` (see [`app/interactors/update_organization_billing.rb`](../../app/interactors/update_organization_billing.rb)).

---

## How to read each row

| Field | Meaning |
| --- | --- |
| `OOB` | local `organizations.out_of_band` flag |
| `Card` | local `organizations.card_added?` (Stripe has a default source/PM) |
| Action | suggested follow-up — case-by-case, NOT automated |

| Class | OOB | Card | Stripe.billing | Action |
| --- | --- | --- | --- | --- |
| **A. Intentional OOB (most)** | true | false | send_invoice | ✅ Working as designed. No action — these are sponsored / member-bucket / invoice-by-request orgs. |
| **B. Card-on-file w/ OOB flag** | true | true | send_invoice | ⚠️ Mixed signal. May be intentional ("we have a card as backup but invoice them"). Confirm with David. |
| **C. Local-says-card, Stripe-says-invoice** | false | true | send_invoice | 🐛 **The bug.** Card exists locally but Stripe never charges it. Manually run a one-off sync OR have the user re-save their card. |
| **D. Card was removed, Stripe-says-invoice** | false | false | send_invoice | 🐛 **Worst case (Wild and Well).** Local flag flipped but card was destroyed/missing. Invoices accrue as `open` indefinitely. Request a card via SetupIntent link. |

---

## Class C — bug, card-on-file (1 org, 2 subs)

| Org ID | Org | Operator | Location | Sub ID | Stripe sub | Plan |
| --- | --- | --- | --- | --- | --- | --- |
| 21 | SLATE Geotech | Cowork Tahoe | Cowork Tahoe | 21872 | `sub_1S8qbdEV6H9PcOfBrwMVriSQ` | Office Lease Plan |
| 21 | SLATE Geotech | Cowork Tahoe | Cowork Tahoe | 21873 | `sub_1S8qbwEV6H9PcOfBLdC6mfsb` | Office Lease Plan |

**Recommended fix:**
```ruby
ActsAsTenant.without_tenant do
  org = Organization.find(21)
  loc = Location.find_by(name: "Cowork Tahoe")
  org.subscriptions.active.each do |sub|
    stripe_sub = Stripe::Subscription.retrieve(sub.stripe_subscription_id,
      api_key: loc.stripe_secret_key, stripe_account: loc.stripe_user_id)
    stripe_sub.billing = "charge_automatically"
    stripe_sub.days_until_due = nil
    stripe_sub.save
  end
end
```
This will let Stripe charge the next renewal against the org's saved card.

---

## Class D — bug, no card (1 org, 1 sub) — Aimee Dalton / Wild and Well

| Org ID | Org | Operator | Location | Sub ID | Stripe sub | Plan |
| --- | --- | --- | --- | --- | --- | --- |
| 1429 | Wild and Well Studio | Untethered | Untethered - Fulton, MO | 24149 | `sub_1TWIsVHk9kSBEyGBBRF14eYw` | Office Lease Plan |

**Status:** active recovery in progress. Stripe Setup Intent link was sent to Aimee Dalton. After she adds a card to the org customer, run the Class C snippet above on this sub and pay invoice `in_1TdLAvHk9kSBEyGB1LyZ8NV2` (the missed $579 from 2026-05-30).

---

## Class B — card on file but `out_of_band: true` (5 orgs)

These are not bugs unless intent has changed. Each likely had OOB set on purpose at some point and has since added a card for a different reason (e.g. day passes, conference rooms, parking).

| Org ID | Org | Operator | Location | Sub ID | Stripe sub |
| --- | --- | --- | --- | --- | --- |
| 327 | Mountain Lux | Untethered | Untethered - Lake Tahoe, NV | 22334 | `sub_1SPtwdDQB7MSd4KBhjYJzcXi` |
| 321 | Luna Lending | Untethered | Untethered - Lake Tahoe, NV | 22533 | `sub_1SZDfjDQB7MSd4KB46ck143C` |
| 315 | Anthony Bradley | Cowork Tahoe | Cowork Tahoe | 22601 | `sub_1SaO29EV6H9PcOfBgBggstzI` |
| 358 | Hennessy Capital Group | Untethered | Untethered - Lake Tahoe, NV | 24058 | `sub_1TRg91DQB7MSd4KBtL9gSuQe` |

Recommended: leave alone unless David confirms they should be auto-charged.

---

## Class A — intentional OOB, no card (33 orgs, 34 subs)

Working as designed. Stripe sends invoices, payment is tracked outside the app (check / ACH / wire / sponsorship). Not exhaustive — full list below for reference.

| Org ID | Org | Operator | Location | Sub ID |
| --- | --- | --- | --- | --- |
| 8 | Eagle Protect | Cowork Tahoe | Cowork Tahoe | 22600 |
| 9 | NHC | Cowork Tahoe | Cowork Tahoe | 22995 |
| 22 | SIG-GIS | Cowork Tahoe | Cowork Tahoe | 22433 |
| 23 | Riva Engineering | Cowork Tahoe | Cowork Tahoe | 22994 |
| 230 | Guild Mortgage | Cowork Tahoe | Cowork Tahoe | 22599 |
| 319 | Tahoe Beach Club | Untethered | Untethered - Lake Tahoe, NV | 23589 |
| 322 | Scale LLP | Untethered | Untethered - Lake Tahoe, NV | 22532 |
| 330 | MUN CPAs | Untethered | Untethered - Lake Tahoe, NV | 22571 |
| 331 | Force Capital | Untethered | Untethered - Lake Tahoe, NV | 22573 |
| 359 | TKBHA | Cowork Tahoe | Cowork Tahoe | 23523 |
| 361 | TAMBA | Cowork Tahoe | Cowork Tahoe | 22235 |
| 364 | Solanna | Untethered | Untethered - Lake Tahoe, NV | 21641 |
| 368 | Justin Sinner | Untethered | Untethered - Lake Tahoe, NV | 24055 |
| 373 | Kyle Gordon | Cowork Tahoe | Cowork Tahoe | 22598 |
| 538 | Keith Price | Untethered | Untethered - Lake Tahoe, NV | 24057 |
| 571 | Sierra Mental Wellness Group | Cowork Tahoe | Cowork Tahoe | 24182 |
| 637 | Culbertson and Gray | Cowork Tahoe | Cowork Tahoe | 22996 |
| 703 | Marcella Foundation | Cowork Tahoe | Cowork Tahoe | 23062 |
| 802 | Camp Richardson Resort | Cowork Tahoe | Cowork Tahoe | 23654 |
| 868 | Brian Hudgens | Cowork Tahoe | Cowork Tahoe | 24056 |
| 968 | Shamus McNutt | Untethered | Untethered - Lake Tahoe, NV | 22574 |
| 1165 | Humane Society of Truckee-Tahoe | Cowork Tahoe | Cowork Tahoe | 22697 |
| 1198 | Oasis Mentis | Cowork Tahoe | Cowork Tahoe | 22569 |
| 1264 | Live TALOHA | Untethered | Untethered - Lake Tahoe, NV | 24083 |
| 1264 | Live TALOHA | Untethered | Untethered - Lake Tahoe, NV | 24084 |
| 1363 | GigaBite | Cowork Tahoe | Cowork Tahoe | 23456 |

Plus the legacy `Rr7IaDQB7MSd4KBjTPkwwPe` sub at the top of the output for an older Untethered org (not enumerated here — pre-2024).

---

## Summary

| Class | Orgs | Subs | Action |
| --- | --- | --- | --- |
| A. Intentional OOB | 26 | 27 | none |
| B. Card + OOB flag | 4 | 4 | confirm intent w/ David |
| C. Bug, has card | 1 | 2 | run sync snippet |
| D. Bug, no card (Aimee) | 1 | 1 | in flight |

**Why no automated sweep:** Class A is the majority and is correct. A blanket "switch all to charge_automatically" would silently break sponsorships and invoice-by-request arrangements. Each case in B/C needs a human nod.

---

## Why the bug existed

`UpdateOrganizationBilling` flipped `organizations.out_of_band` locally but never told Stripe. The Stripe subscription's `billing` field was set once at creation by `StripeSubscriptionFactory.for(...)` based on whichever value `org.out_of_band?` had **at sub-creation time**. Subsequent flips of the flag (e.g. via the operator UI when an admin clicks "add a card for this org") only updated our DB, leaving Stripe in its original mode forever.

`UnmarkCustomerAsOutOfBand` / `MarkCustomerAsOutOfBand` exist for the **User** path and do iterate subscriptions to update Stripe. The **Organization** path was never given the same treatment. This PR adds that.
