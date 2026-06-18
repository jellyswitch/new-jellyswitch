# Day Pass Bundle revenue is recognized at the sale, not per burn

A **Day Pass Bundle** contributes to operator-facing revenue totals **once, on the day it is purchased, at the pack price** — the flat `DayPassType.amount_in_cents` of the N-Pack SKU, which is the exact one-time charge (volume discount baked in, *not* quantity × a per-pass price). A subsequent **burn** (a bundle-sourced `DayPass` minted on entry) contributes **$0** — it spends already-recognized prepaid value. Daily revenue surfaces (notably "Who's coming today" / Today's Activity) therefore **add the bundle sale on its purchase day** and **exclude bundle-sourced entry passes** from the day-pass revenue sum.

## Context

A single Day Pass is bought and used as one event, so the daily-activity endpoint can fairly sum `DayPass → DayPassType.amount_in_cents` for today's passes. A Bundle breaks that 1:1 assumption: the money arrives at purchase (a multi-pass invoice), but the *passes* arrive later, one per visit, each minting an internal `DayPass` row for the day of entry.

Those minted rows look exactly like ordinary day passes to a naive `DayPass.where(day: today)` revenue sum — so without intervention the daily total **double-counts**: once when the pack sells, and again every time a prepaid pass is burned. Meanwhile the genuine cash event — the bundle sale — isn't counted at all, because the endpoint only sums day passes, reservations, and new subscriptions.

The codebase already provides the hooks: `DayPass.bundle_sourced` / `.not_bundle_sourced` scopes (joined through `DayPassBundleRedemption` entry rows), a `DayPassBundle.purchased_at` timestamp, and the pack price on `bundle.day_pass_type.amount_in_cents` — the same field the controller already sums for single day passes. (The burn-side exclusion already shipped as adversarial-review fix "I1"; what remained was counting the sale.)

## Considered Options

- **(a) Per-visit accrual.** Recognize nothing at sale; recognize a per-pass fraction of the bundle price as each pass burns. Matches accrual accounting, but it's surprising for a small operator's "money in today" dashboard, requires allocating a price per burn, and strands revenue for never-redeemed passes.
- **(b) Count the burn at the day-pass face price.** Treat each bundle entry like a normal day-pass sale. Simplest to *not* build — but double-counts against the sale and overstates daily revenue every time someone walks in on a pack.
- **(c) Cash basis — count the sale, zero the burn (chosen).** Recognize the full pack price on the purchase day; bundle-sourced burns add $0.

## Why (c)

1. **It matches the mental model of the surface.** "Who's coming today" answers "how much money came in today?" A pack sold today *is* money in today; a prepaid walk-in is not.
2. **It's consistent with how subscriptions already work** here — a new subscription is counted once, on creation, at the plan amount. Bundles now behave the same way: recognized once, at sale.
3. **No double-counting, no stranded revenue.** Every dollar is counted exactly once, on the day it was actually collected, regardless of whether or when the passes are burned.
4. **It reuses the same price field the surface already trusts.** The pack price *is* `day_pass_type.amount_in_cents` (the flat SKU charge, discount baked in), so the bundle sale is summed exactly like the day-pass and plan amounts already are — no special invoice join, no per-pass arithmetic, and consistent with the rest of the endpoint. Because "today's activity" only counts same-day purchases, there is no price-drift window to worry about.

## Consequences

- **Daily revenue sums must exclude bundle-sourced passes** — use `DayPass.not_bundle_sourced` wherever today's day-pass revenue is totaled (e.g. `Api::V1::Admin::TodaysActivityController`).
- **Bundle sales must be added to daily revenue** on their purchase day (`DayPassBundle.purchased_at`), summed at `bundle.day_pass_type.amount_in_cents` (the flat pack price — never `× quantity`).
- **The feed and the daily total read the same field** (`day_pass_type.amount_in_cents`), so the amount on a purchase's feed item always agrees with the revenue it contributed — and matches how the single-day-pass feed item already sources its amount.
- **Bundle-sourced entries still appear as people** in attendance views — they are excluded from the *revenue* sum only, never from the *who-is-here* list. A prepaid walk-in is a real visit worth $0 today.
- **Refunds are out of scope here.** Recognition follows the sale; a later refund/adjustment is a separate event and does not retroactively rewrite the original purchase-day feed entry.
