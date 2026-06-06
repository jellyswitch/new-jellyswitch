# OfficeRnD → Jellyswitch: Import Spec (developer-facing)

Target backend: this repo (`jellyswitch-production`). Tenancy via `acts_as_tenant`
(`Operator` = tenant, scoped by subdomain). Stripe Connect credentials live on
`Location` (`stripe_user_id`, `stripe_access_token`, `stripe_publishable_key`).

## Guiding principle

Reuse the space's **existing** Stripe account (Connect). Historical billing data
already lives there as real Stripe objects, so we **anchor** Jellyswitch records to
existing Stripe IDs rather than synthesizing new charges. **The importer must never
create a Stripe charge.**

## Schema facts that shape the importer

### Invoice (`invoices`)
- Polymorphic billable: `billable_type` ∈ {`"User"`, `"Organization"`}, `billable_id`.
- Money in cents: `amount_due`, `amount_paid`. Dates: `date`, `due_date`.
- Status (string enum): `open, uncollectible, void, paid, refunded`.
- Stripe refs: `stripe_invoice_id`, `stripe_payment_intent_id`. Scoping: `operator_id`, `location_id`.
- **Callbacks:** only `after_update :log_payment_activity_if_status_changed` (writes an
  Activity row). **No `after_create`/`after_save` that calls Stripe.** ⇒ `Invoice.create`
  for historical rows is Stripe-safe.
- Refunds live in a separate `refunds` table (`invoice_id`, `stripe_refund_id`, `amount`), no callbacks.

### Customers
- `User` — `email` unique **per `operator_id`**; `belongs_to :organization, optional`.
  Stripe customer id is **not** on `User` anymore (deprecated col) — it lives on…
- `UserPaymentProfile` — `(user_id, location_id)` unique; holds `stripe_customer_id`,
  `card_added`, `bill_to_organization`. **This is where a member's Stripe customer maps.**
- `Organization` — `name`, `stripe_customer_id`, `owner_id`, `billing_contact_id`.
- Internal-ledger only (NOT in Stripe): `User.credit_balance`, `User.childcare_reservation_balance`.

### Billing config
- `Plan` — `name`, `interval` (daily/weekly/monthly/quarterly/biannually/annually),
  `amount_in_cents`, `stripe_plan_id`, `credits`, `included_meeting_room_minutes`, scoped by location.
- `Subscription` — polymorphic `subscribable` & `billable`, `plan_id`, `stripe_subscription_id`,
  flags `active/pending/paused/cancelling_at_end_of_billing_period`, `start_date`.
  For historical subs with no live Stripe sub: leave `stripe_subscription_id` nil and
  mark not-active so lifecycle code doesn't try to manage a non-existent Stripe sub.
- `DayPass` / `DayPassType` — `amount_in_cents`, `code`, `included_meeting_room_minutes`.

## Field mapping (canonical → Jellyswitch)

| Canonical CSV field | Jellyswitch target | Notes |
|---|---|---|
| `email` | `User.email` | required; matched case-insensitively, scoped to operator |
| `name` | `User.name` | required |
| `phone` | `User.phone` | placeholder if blank (`User` requires phone) |
| `company` | `Organization` (find/create) + `User.organization_id` | |
| `stripe_customer_id` | `UserPaymentProfile.stripe_customer_id` (+ `card_added`) | per-location |
| `membership` | `Subscription.plan_id` via plan-mapping | distinct values mapped to `Plan` in the wizard |
| `status` | gates `User.approved` / subscription `active` | |
| invoice rows | `Invoice` anchored to `stripe_invoice_id` | display-only history |

## Import pipeline (interactors)

1. **Connect Stripe** — set Location's Connect credentials to the existing account.
2. **Parse** — `Officernd::CsvParser` → headers + rows.
3. **Auto-detect columns** — `Officernd::ColumnDetector` pre-fills the column mapping.
4. **Build preview (DRY RUN)** — `Onboarding::Import::BuildPreview` → per-row analysis,
   match status (existing vs new), distinct membership values + their plan mapping,
   warnings/errors. **No writes.** ← *implemented*
5. **Commit** — `Onboarding::Import::Commit` (transactional, idempotent, `ActsAsTenant.with_tenant`,
   **no Stripe calls**). Idempotency keyed on Stripe IDs / email. ← *implemented*
   - Creates/updates `User` (via `admin_created` flag → bypasses phone+terms; placeholder
     password, member resets via email), `UserPaymentProfile`, `Organization`, and a
     `Subscription` on the **person** when a membership maps to a `Plan`.
   - `stripe_subscription_id` left nil here; the real Stripe subs already exist in the
     connected account and can be backfilled later via `location.list_stripe_subscriptions`.
   - Per-row validation failures are recorded as skips; only unexpected errors roll back.

> **Not yet covered:** historical **Invoice** backfill (anchored to existing
> `stripe_invoice_id`) is a separate importer/CSV — see the migration plan. Members +
> memberships ship first.

## Idempotency & safety rules

- Re-running must not duplicate: upsert Users by `(operator_id, lower(email))`;
  Invoices by `stripe_invoice_id` (or `number`); UserPaymentProfiles by `(user_id, location_id)`.
- Wrap commit in a DB transaction; collect a per-row result log.
- Never call Stripe in the importer. Historical invoices are inserted as records only.
- `csv` is a Ruby default gem on 3.3; on a **Ruby 3.4+** upgrade, add `gem "csv"` to the Gemfile.

## Entry points

- Rake (works today against a file on disk):
  - `bin/rails 'officernd:dry_run[/path/to/members.csv, <location_id>]'`
- The onboarding wizard (see `03-wizard-plan.md`) calls the same interactors.
