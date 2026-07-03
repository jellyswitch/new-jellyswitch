# Member-initiated redemption is the same burn as door entry; redeeming is not door access

A bundle pass can be spent three ways — the **door auto-burn** on a successful unlock, an in-app **"use a pass for today,"** or that same action from the **web account** — but all three are one act through the single `Billing::DayPassBundles::ConsumeOnEntry` authority: today-only, never scheduled, guarded by the same precedence (membership / lease / reservation / non-bundle day pass take precedence) and burned at most once per business-day window. A redemption mints **today's `DayPass`** (the *right* to be present); it does **not** open a door. At app-only spaces a web redeem therefore **confirms the pass and hands off to the app** — the app stays the key.

## Context

The bundle model is "burn on entry" (ADR 0008 / 0009): a pass is spent by physically opening the door, which mints today's Day Pass and decrements the bundle. The app later added an explicit in-app "redeem today" — the same `ConsumeOnEntry` — for a member who wants to use a pass without first tapping a door.

But **most purchases happen on the web**, where a bundle was neither visible nor usable: a buyer (e.g. a 2-pack) would purchase, find no redeem affordance and no pointer to the app, and "disappear" — the concrete failure that prompted this work. The fix needs a web redeem button.

Naively, a web "redeem" could mint today's pass straight from a browser. Two hazards: (a) it burns a pass on a day the member may never show, breaking "burn on entry"; and (b) at app-only doors it still cannot let them in, creating a *new* "I redeemed but I'm locked out" failure.

## Decision

- **One authority, three triggers.** Web and app redemption call the **same** `ConsumeOnEntry` as door entry — no parallel billing path. It stays today-only, idempotent per business-day window, and a no-op when anything else already covers today.
- **Frame it as "use a pass for today,"** done when heading in. A mis-click is recoverable through the existing `admin_restore` redemption.
- **Redeeming ≠ entering.** Redemption grants the right to be present (mints today's Day Pass); the **app remains the key** to the door. A web redeem's success state hands off to the app (download / open → unlock); it never pretends to grant entry.
- **No web-side door access is built.** Doors stay app/credential-gated.

## Consequences

- A single authority for every burn (door, app, web) → no drift in guards, idempotency, or revenue treatment (burn is still $0; revenue recognized at sale — ADR 0009).
- Premature burns are possible (redeem from home) but bounded: today-only, once-per-day, reversible via admin restore.
- At app-only spaces the web redeem is a **convenience layer, not a replacement** for the app — so the post-purchase **app hand-off** (a download prompt on every purchase confirmation + the onboarding email) is the *primary* fix; web redeem is secondary.
- A future reader sees why a browser may burn a prepaid pass yet still cannot open a door, and why no web door-access path was built.
