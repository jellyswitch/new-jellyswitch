# New-Operator Onboarding Runbook

Everything below was learned the hard way onboarding Tahoe Longhouse
(June–July 2026). Follow it in order and the next operator's ramp is a
checklist instead of a firefight. Companion docs: export instructions the
operator receives ([01](01-export-instructions.md)), the developer-facing
import spec ([02](02-import-spec.md)).

## 0. Ground rules

- **Connect the operator's REAL Stripe account on day one. Never a
  throwaway.** TLH started on a scratch account and reconnected to their
  real one mid-ramp; every invoice, subscription, and customer created
  before the switch was orphaned on the old account. The fallout consumed
  a week: un-voidable invoices, stale stored customer ids that fail future
  charges, hand-run cleanup. If a reconnect ever happens anyway, see §6.
- **Imports must produce functional records, not bookkeeping.** A day-pass
  invoice is not enough — the member must hold a `DayPass` row for the
  scheduled day (check-in, door access, and Today's Activity all read from
  it). Same for pack balances (`DayPassBundle.passes_remaining`), leases
  (`OfficeLease` with real dates + subscription), and memberships (active
  `Subscription`). If the app can't act on it, it isn't imported yet.

## 1. Platform setup (before any data)

| Item | Where | Notes |
|---|---|---|
| Operator + location, subdomain, branding | superadmin UI | |
| `billing_state: "production"` | Operator | test mode silently skips real charges |
| Stripe Connect (real account) | operator settings | verify `location.stripe_user_id`; publishable key is env-served, not the DB column |
| Notification toggles | Operator | TLH runs ALL on (reservation/signup/checkin/day-pass/refund/feedback/membership/post/paid-room) |
| Push: `bundle_id` + Firebase server key | Apple/Firebase consoles + operator | **manual console work; silently no-ops if missing** — send a real test push per platform |
| Email templates | auto-seeded per operator | verify ~16 `ProductEmailTemplate` rows exist |
| Plans (individual + lease types), day-pass types | admin UI | avoid duplicate type names; blank required numeric fields are rejected since PR #662 |
| Rooms | admin UI | a room nobody can book = `visible` + (`rentable` with rate, or `include_with_day_pass`) |
| Doors / beacons (Kisi) | admin UI | beacons need a full app relaunch to range |
| Offices | admin UI | leases attach in §3 |

## 2. CSV imports (`lib/tasks/officernd.rake` — all idempotent)

Re-running a full CSV is always safe: existing rows are matched and skipped.

Getting a CSV onto a production dyno:

```sh
B64=$(base64 -i members.csv)
heroku run -a jellyswitch-production \
  "echo '$B64' | base64 -d > /tmp/members.csv && \
   bin/rails 'officernd:dry_run[/tmp/members.csv,<LOCATION_ID>]'"
```

Order matters — members before invoices (invoice rows resolve billables by
email), invoices before derived day passes:

1. `officernd:dry_run` → `officernd:import` (members). The members CSV
   drives everything: `Company` column upserts Organizations and links the
   member; **blank Company = individual** (never wrap a solo person in an
   org); `Stripe Customer` column attaches the payment profile. The
   separate *companies* CSV is reference-only — **never import it
   directly** (TLH's listed "Openrouter" for a person who is an
   individual).
2. `officernd:invoices_dry_run` → `officernd:import_invoices`.
3. Day passes: derive a CSV from the invoice sheet — one row per day-pass
   invoice, `Date` = invoice date, honoring "day pass for <date>" notes in
   the trailing column, skipping refunds/negative amounts — then
   `TYPE_MAPPING='{"Day Pass":<type_id>}' officernd:import_day_passes`.
   Pack purchases get their first-visit day here; the rest of the pack is
   the bundle balance (§3).

Known row-level traps: section-marker rows ("Added Jul-12") skip cleanly;
email typos in the invoice sheet fail billable lookup — fix by hand against
the members sheet; the same person can appear person-named in the
companies sheet (they're an individual — trust the members sheet's blank
Company column, and confirm with the operator when in doubt).

## 3. Functional records (the part invoices don't cover)

- **Bundles**: every balances-sheet row becomes a `DayPassBundle`
  (`quantity_purchased`, `passes_remaining`, `day_pass_type`,
  `purchased_at`). Use the *column* value for remaining, not stale note
  text.
- **Leases**: every occupied office gets an `OfficeLease` with real
  `start_date`/`end_date` and an attached subscription. On renewals,
  **deactivate the superseded subscription** or MRR double-counts (TLH:
  expired lease's $950 sub sat active next to the $850 renewal).
  Individual tenants lease directly (`user_id`, no organization) — they
  count as active members since PR #663.
- **Memberships**: every CSV-active Full-Time member holds an active
  `Subscription` (personal, or via their organization).

## 4. Post-import audit (run all of these; each caught something at TLH)

Via `heroku run bin/rails runner` against the new operator/location:

- Every CSV-active member → active subscription (personal or org).
- Every lease in-window (`now() BETWEEN start_date AND end_date`) with an
  active subscription; no superseded subs still active.
- `DayPassBundle.sum(:passes_remaining)` per email == balances sheet.
- Scheduled/future day passes exist as `DayPass` rows.
- Zero dangling references: invoices/day passes/reservations/subscriptions
  whose user is gone; feed items whose `user_id` or `blob["invoice_id"]`
  no longer resolves.
- Rooms: every room the operator expects bookable satisfies §1's rule.
- Report sanity: `Jellyswitch::Report.new(operator, location)` — always
  pass BOTH args (a Location passed as the first arg half-works and breaks
  the `for_operator` joins) — check `total_active_member_count` and
  `active_member_breakdown` against reality.

## 5. Go-live vetting

- Public pages 200 over real HTTP: `/`, `/login`, `/signup` on the brand
  subdomain.
- Test push notification lands on iOS and Android.
- A real end-to-end purchase on the operator's Stripe (day pass is the
  cheapest): charge succeeds, invoice + `DayPass` row created, feed item
  appears.
- `heroku logs` clean of 500s while the operator's admins click through
  feed, invoices, members, rooms, offices.

## 6. If data surgery is ever needed (deletions, reconnects)

- **Deleting users**: 15 tables hold FK constraints to `users` (grep
  `add_foreign_key .* "users"` in schema.rb) — clear those rows first.
  Feed items/comments cascade since PR #664, but out-of-band deletes (raw
  SQL) must clean `feed_items` + `feed_item_comments` themselves.
- **Deleting invoices**: refund feed items reference `blob["invoice_id"]`
  — the feed skips orphans since PR #665, but purge them anyway.
- **After a Stripe reconnect**: Stripe object ids embed chars 6–15 of the
  account token (`in_1Tu4N5By0vFaUPkp…` ↔ `acct_1ThMweBy0vFaUPkp`), so
  cross-account orphans are findable with SQL `LIKE`. Also verify every
  stored `cus_` id (users + `user_payment_profiles`) exists on the new
  account — clear stale ones so the app mints fresh customers. Orphaned
  *open* invoices void locally since PR #661.
