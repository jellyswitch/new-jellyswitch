# Day Pass Daily Limit by Type — Design

**Date:** 2026-07-12
**Status:** Approved by David
**Motivating case:** Cowork Tahoe sells "Day Office" passes ($100, DayPassType 1343) but has a
fixed number of physical day offices. Nothing stops members from buying more passes for a day
than there are offices. Operators need a per-type cap on how many passes can exist for a given day.

## Decisions (confirmed with David)

1. **Every pass counts.** The cap models physical capacity. Purchased, staff-comped, and
   bundle-scheduled passes of the type all count toward a day's tally, regardless of how they
   were paid.
2. **Staff can exceed the cap.** The cap hard-blocks member self-serve paths only. Staff
   creating or comping a pass through admin can go over — they can judge real occupancy.
   Their rows still count toward the tally.
3. **Web-only config surface.** The limit is set on the web day-pass-type form. No mobile
   admin change (mobile admin day-pass-type screen is read-only; config is a web task per
   standing decision).
4. **No mobile buy-screen change in v1.** The app already surfaces server 422 messages in
   alerts on every affected flow. Graying out sold-out dates in the date picker is an optional
   follow-up (needs a date-aware availability endpoint) — explicitly out of scope for v1.

## Data model

Migration adds one column to `day_pass_types`:

```ruby
add_column :day_pass_types, :daily_limit, :integer, null: true
```

- `nil` (default, and the value for all existing rows) = unlimited.
- Positive integer = maximum passes of this type that may exist per calendar `day`
  (per location — DayPassType is already location-scoped).

Model validation:

```ruby
validates :daily_limit, numericality: { only_integer: true, greater_than_or_equal_to: 1 },
                        allow_nil: true
```

## Count semantics

One shared gate on `DayPassType`:

```ruby
# Every DayPass row of this type on that day counts — purchased, comped,
# bundle-sourced — because the limit models physical capacity (e.g. the
# building has 2 day offices), not sales volume.
def daily_limit_reached?(day:, location:)
  return false if daily_limit.nil?
  day_passes.where(location: location, day: day).count >= daily_limit
end
```

## Enforcement points (member self-serve only)

| Path | Where | Behavior at limit |
|---|---|---|
| Buy a single pass for a chosen date (API) | `Api::V1::DayPassesController#create` (single-pass branch) | 422: "Day Offices are fully booked for July 15. Try another day." |
| Buy a single pass for a chosen date (web) | `Operator::DayPassesController#create` (member buy flow) | `flash[:error]` + `turbo_redirect` back to the date picker: "Day Offices are fully booked for 07/15/2026. Try another day." Uses `short_date` (MM/DD/YYYY) — a deliberate per-surface idiom; API surfaces use `%B %e`. |
| Schedule a day from a bundle | `Billing::DayPassBundles::ScheduleDay` (per date), **opt-in** via an `enforce_daily_limit` context flag passed only by the member endpoint (`Api::V1::DayPassesController#schedule`). The flag exists because the staff burn-for-customer path (`Api::V1::Admin::MembersController#schedule_bundle_days`) shares this interactor and must stay ungated. | New `:sold_out` outcome carrying the failed date + type; controller maps it to the same message |
| Move an unused pass to another day | `Api::V1::DayPassesController#reschedule` — check the **target** day; skip the check when the target equals the pass's current day (the row would count against itself) | 422, same wording |
| Buy a single pass via the public concierge widget (no login) | `Concierge::PublicCheckout#purchase_day_pass`, reached anonymously from `Embed::ConciergeController#purchase` (which resolves any available+visible type at the location — same gate needed here) | Interactor `context.fail!(message: ...)` → `Embed::ConciergeController#purchase` renders `{ok:false, message:...}` at 422; same `%B %e` wording. Always today (`context.day` is never set by the widget), not a chosen date. |

Note: the web `reschedule` action (`Operator::DayPassesController#reschedule`) is the **admin**
surface (member reschedule is mobile-only), so it is a bypass path, not a gated one.

The check runs as a pre-check before create/move. Message template:
`"#{type.name.pluralize} are fully booked for #{day.strftime('%B %e')}. Try another day."`

### Explicitly NOT blocked (bypass by design)

- **Admin create/comp** — web `Operator::Admin::DayPassesController#create`, mobile admin
  `members/:id/create_day_pass`, web admin reschedule, and admin
  `schedule_bundle_days` (no `enforce_daily_limit` flag). Staff pass through; rows still count.
- **Door burn / redeem today** — `Billing::DayPassBundles::ConsumeOnEntry`. Never strand
  someone at the door over a cap.
- **Room-booking coverage pass** — the `Billing::Reservations::EnforceCoverage` chain
  (reuse → bundle → buy, ADR 0019). Blocking would break a booking already made; the pass
  is committed as part of the reservation.
- **Bundle purchase itself** — buying an N-pack has no date; only scheduling/burning is
  date-bound and covered above.
- **`operator/day_passes#redeem_code`'s free-pass branch only** — a redeemed code for a
  `free?` type routes straight to `Billing::DayPasses::RedeemFreeDayPass` (the ungated
  `SaveDayPass` authority), today-only, with no daily-limit check. This is the one
  code-redemption path that's actually ungated. A redeemed *paid* code instead redirects to
  `#redeem_paid`, whose checkout form POSTs to the same `#create` action used by the regular
  web buy flow above — **that path IS gated**, so a capped hidden type reached via an access
  code is still blocked. (The mobile API create path with an access code is likewise gated —
  it runs through the single-pass create pre-check.) Redeemed rows still count toward the
  tally either way. Revisit `redeem_code`'s free-pass branch if an operator ever puts a code
  on a capped free type.

## Admin UI (web)

`app/views/operator/day_pass_types/_form.html.erb` (and the edit form if separate) gains:

- Label: "Max sold per day (leave blank = unlimited)"
- `number_field :daily_limit, min: 1, step: 1, placeholder: "Unlimited"`
- Permit `:daily_limit` in `Operator::DayPassTypesController` strong params.

Mobile admin API (`Api::V1::Admin::DayPassTypesController`) is untouched in v1: its permit
list simply doesn't include the new column.

## Concurrency

Two members grabbing the last slot at the same instant can both pass the count check. Accepted
for v1 — same posture as the existing reservation-overlap guard (no DB lock, parked). Volume at
current operators makes this a rare, staff-fixable edge (staff can comp/refund). If it ever
bites, the fix is a `with_lock` on the DayPassType row around count+create.

## Known limits (accepted for v1)

- **Nil-location legacy passes** sit outside every real location's tally: the
  count is exact-match on `location_id`, so a legacy pass with NULL location
  neither counts toward nor is gated by any location's cap. App-created passes
  always carry a location; this only affects odd legacy rows.
- **Multi-bundle members with mixed types**: bundle day-scheduling gates the
  soonest-expiring eligible bundle's type. If that type's day is full, the
  member gets "fully booked" even if another bundle of a different, uncapped
  type could cover the day. Consistent with the single-active-bundle
  assumption.
- **Emails enqueued inside the scheduling batch transaction** (pre-existing):
  a mid-batch failure after a burn can leave an already-enqueued product email
  for a rolled-back burn. `:sold_out` adds a fourth route into this
  pre-existing behavior; not made worse by this feature.

## Testing

- **Model:** `daily_limit_reached?` — nil limit always false; at/below/above threshold;
  scoped to day + location; complimentary and bundle-sourced rows count.
- **Request, per member path:** blocked at limit (422 + message), allowed below, unlimited
  when nil. Paths: API single-pass create, bundle `schedule`, `reschedule` (target day full,
  and same-day move allowed at limit), plus web member buy.
- **Interactor:** `ScheduleDay` returns `:sold_out` with the flag set; schedules past the
  limit without the flag.
- **Bypass:** admin `schedule_bundle_days` succeeds past the limit (request-level);
  `SaveDayPass` — the pass-creation authority behind every staff add/comp flow — creates
  past the limit (interactor-level; a request test of admin `create_day_pass` would need
  heavy Stripe scaffolding since `CreateStripeInvoice` calls Stripe even for $0 passes);
  `ConsumeOnEntry` mints past the limit. The reservation-coverage chain is structurally
  ungated (no gate call site) — no dedicated test.

## Out of scope (v1)

- Graying out / disabling sold-out dates in the mobile date picker (needs a per-date
  availability endpoint; revisit if members complain about buy-then-error friction).
- Mobile admin config field for the limit.
- Row-locking for the concurrent-purchase race.
- Any change to door access logic.
