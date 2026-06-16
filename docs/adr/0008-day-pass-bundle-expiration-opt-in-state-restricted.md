# Day-pass bundle expiration is opt-in, disclaimer-gated, and state-restricted by data

A **Day Pass Bundle** (prepaid N-Pack) **never expires by default.** Expiration is an optional, per-product setting (on `DayPassType`, measured from purchase). Enabling it requires an explicit operator acknowledgment of a legal disclaimer. A **maintainable data list of expiration-restricted states** (California from day one) **hard-blocks** expiration for any product whose location is in a restricted state; elsewhere it is allowed behind the disclaimer. The per-state legal mapping lives in **data, never in code logic**.

## Context

Prepaid bundles are stored value. California Civil Code §1749.5 prohibits expiration dates on gift certificates sold for cash, and a prepaid day-pass pack very plausibly qualifies — so it cannot expire in California. Other states vary, the federal CARD Act adds a murky 5-year floor for "gift cards," and the law changes over time. This is **not legal advice**; the operator (with counsel) owns the decision. Tahoe Longhouse straddles the CA/NV border, so the *location's* state is a real, load-bearing variable — and `DayPassType` already carries `location_id`.

## Considered Options

- **(a) Never offer expiration.** Perpetual always. Simplest and safest, but operators in permissive states lose a legitimate option.
- **(b) Optional + disclaimer only.** Operator can set expiration anywhere after acknowledging a disclaimer; no state enforcement. Puts all risk on the operator, including in clearly-prohibited states like CA.
- **(c) Optional + disclaimer + data-driven state block (chosen).** Off by default; opt-in behind a disclaimer; hard-blocked where a maintainable restricted-states list (CA initially) says so, keyed off the product's location state.
- **(d) Hardcode per-state legal rules in code.** Encode CA/NV/… rules as branching logic. Rejected — bakes uncertain, changing legal conclusions into code; every legal clarification becomes a deploy, and a wrong constant is a compliance bug.

## Why (c)

1. **Default-perpetual is the safe baseline** and matches the most restrictive regime (CA) with zero configuration.
2. **Legality follows the location**, and the location's state is already derivable — so the guardrail can be automatic, not operator-judgment.
3. **The legal mapping is uncertain and will change.** Keeping "which states restrict expiration" in an **editable data list** (plus a mandatory disclaimer) means counsel can revise NV or any other state without a code change — and the code never asserts a legal conclusion, only "is this state on the restricted list?".
4. **It still gives the operator the option** they asked for, exactly where it's lawful.

## Consequences

- **Expiration is configured per product** (`DayPassType`), not per operator — and is **inert unless explicitly enabled**.
- **A restricted-states data list** (e.g. `%w[CA]` to start) must be maintained as counsel advises. Adding/removing a state is a data edit, not a deploy of new logic.
- **Depends on the location having a state** (address). A `DayPassType` whose location has no resolvable state must be treated as restricted (fail safe — no expiration) until the address is set. (Ties into Tahoe Longhouse onboarding, where the address was an open item.)
- **A legal disclaimer is mandatory UI** wherever expiration can be enabled. The system presents it; it is not legal advice and does not absolve the operator.
- **Passes lapse at expiry only for opted-in products in non-restricted states.** Everywhere else (the default), passes are perpetual — consistent with the **Day Pass Bundle** glossary entry.
- This decision is intentionally conservative: when state/address is unknown or the law is unclear, the system declines to expire.
