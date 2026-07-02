# Passwordless login is a 6-digit emailed Login Code, not a magic link

A member can log in **without a password** by requesting a **Login Code** — a single-use **6-digit numeric code** emailed to them, valid **10 minutes**, that authenticates them on entry *and* marks their email **confirmed** in the same act. It is an **emailed code the user types**, never a clickable magic link. It **coexists** with password login (an additional door to the same account, password untouched) and is scoped to one operator. Phase 1 is **login only** for accounts that already exist; passwordless *signup* is explicitly deferred.

## Context

This is the last piece of the signup spam-hardening effort. The triggering failure: a real signup (Tim Flanagan) confirmed-limbo'd — he created an account but never completed email confirmation, and (pre-fix) web login hard-blocked unconfirmed members. We softened that gate (let them in + a verify nudge), but the *root* fix is to make "prove you own this inbox" and "log in" a **single step** so the limbo can't form. Receiving an emailed code is exactly that proof.

Constraints from the existing system:
- **Users are operator-scoped** (`User.find_by_operator(email:, operator_id:)`); the same email can exist under multiple operators. Any code flow must carry the tenant (subdomain header on API, host on web).
- **Two existing token patterns to mirror:** password reset stores a *digest* of a random token in `users.reset_digest` + `users.reset_sent_at` with a time-window expiry; email confirmation uses `confirmation_token` / `valid_confirmation_token?`. Both use `User.digest` (bcrypt) + `User.new_token`. We reuse this shape rather than invent storage.
- **Mobile auth is a 30-day JWT** from `generate_token`; web auth is the session `log_in`. The code flow must terminate in the *same* credential issuance as password login so post-login routing is identical.
- **Deep linking has been repeatedly brittle** in the mobile app (cold-start routing, the "Main"-nesting bug). This is the decisive reason a code beats a link.
- **Rate limiting already exists** — `Rack::Attack`, Redis-backed across dynos, with an established `signup/ip` 5/min throttle to mirror.
- **ADR 0003 (Spam Guard)** already exempts transactional mail (confirmations, password resets) from the marketing cool-down, in both directions.

## Considered options

- **(a) Magic link (emailed URL that logs in on tap).** Smoothest on web, but on mobile it depends on robust deep-linking — the single most fragile surface in this app (cold-start budget, navigator nesting). A link that lands a logged-out cold-start app on the wrong screen recreates a limbo of its own. Rejected for mobile risk.
- **(b) 6-digit emailed Login Code, typed (chosen).** Identical two-step flow on web and mobile, **zero deep-link dependency**. Triggers OS one-time-code autofill on the phone. Reuses the reset-digest storage and the JWT/session issuance verbatim. The 6-digit guess space is closed by an attempt cap, not by code complexity.
- **(c) Both — link on web, code in app.** Best per-surface UX, but two redemption paths and two sets of edge cases to build and keep correct, for marginal web gain. Deferred; the code primitive can grow a web link later without rework.
- **Storage: dedicated `LoginCode` table vs columns on `User`.** Chose **columns on `User`** (`login_code_digest`, `login_code_sent_at`, `login_code_attempts`) — one active code per user is the exact desired semantic (a new request overwrites the old, auto-invalidating it), it matches the understood `reset_digest` pattern, and no issued-code *history* is wanted (transient secrets). A table would only earn its place for audit/multiple-concurrent-codes, neither of which is needed.

## Why (b)

A typed code is the only option that is **equally robust on both surfaces** while reusing every existing primitive (digest storage, `log_in`/`generate_token`, `Rack::Attack`, the transactional-mail exemption). It removes the deep-link variable entirely — the thing most likely to regress. It is simultaneously the *lowest-friction* path for a real member and a *dead end* for spam: a code can only be completed by someone who can read the mailbox, so it widens the spam surface by nothing (and complements the front-door blocks — disposable #537, MX #540 — rather than competing with them). And it makes the just-shipped verify-email nudge self-clearing for anyone who logs in this way.

## Design envelope (the numbers, and why)

- **Code:** `SecureRandom.random_number(1_000_000)`, zero-padded to 6 digits, stored only as `User.digest(code)`. Never persisted or logged in plaintext.
- **Expiry:** 10 minutes (`login_code_sent_at < 10.minutes.ago` ⇒ expired). Short, since a code is used immediately; long enough to absorb the known SendGrid greylisting/deferral on some recipients.
- **Single-use + attempt cap:** consumed (digest cleared) on success; `login_code_attempts` increments on each wrong guess and at **5** the code is invalidated (silent — "request a new code", **no account lock**, to deny a lock-out DoS). This caps the brute-force budget at 5 guesses per issued code → 5-in-1,000,000 per code, the *primary* defense.
- **Rate limits (Rack::Attack, mirroring `signup/ip`):** request-code **5/min per IP** + **3 per 15 min per email** (so an attacker can't multiply guesses by re-requesting fresh codes, and a victim can't be email-bombed); verify-code **~10/min per IP** as defense-in-depth.
- **One-step confirmation:** a successful verify sets `email_confirmed = true` (if not already) in the same transaction it logs in.
- **No enumeration:** request-code *always* returns the same "if an account exists, we've sent a code" success — identical to `forgot_password`. Code is sent only when the user is found.
- **Authentication parity:** verify works regardless of `approved?` (approval gates coverage/actions, not authentication — same as password login today) and issues the identical credential (`generate_token` / `log_in`) and the identical `#login` response payload (including `needs_email_confirmation`, now `false`).
- **Endpoints:** API `POST /api/v1/auth/request_login_code` + `POST /api/v1/auth/verify_login_code` (both in the auth skip-auth list); web request/verify forms off `/login` (tenant from host), member types the code — no link.
- **Email:** new transactional `UserMailer.login_code` via `deliver_now`. Per ADR 0003 it never trips and is never suppressed by the Spam Guard cool-down — a login code MUST always send and MUST NOT pause a drip.
- **Term:** member-facing **"login code"** (see CONTEXT.md); avoid "OTP"/"passcode"/"magic link" in UI.

## Consequences

- **Three new `users` columns** (`login_code_digest:string`, `login_code_sent_at:datetime`, `login_code_attempts:integer default 0`) — additive, nullable, no backfill.
- **Confirmation can now happen via two paths** (the existing email-confirmation link *and* a successful login code). `confirm_email!` / the `email_confirmed` flag remain the single source of truth; the login-code path just calls into the same flip, so the verify-email nudge clears regardless of which path confirmed.
- **A member with no password is still unreachable in Phase 1** — login codes only authenticate *existing* accounts, and signup still sets a password. Passwordless signup (accounts with a null password digest, and everything that implies for `authenticate`) is **deferred to Phase 2**, explicitly not foreclosed: the code primitive is the prerequisite, and a Phase-2 ADR would cover null-password accounts.
- **Security review is short** because storage and issuance are "the same as password reset + the same as password login." The only genuinely new surface is the attempt-cap brute-force envelope, which is documented above.
- **Operators see no new setting** — login codes are always available, like password reset. No per-operator toggle (consistent with treating anti-limbo as platform standard, not opt-in).
- **Build is phased:** backend (columns + endpoints + mailer + throttles + RSpec) ships first; the mobile UI (a LoginScreen "Email me a login code" affordance + a code-entry screen) and the web request/verify forms follow. This ADR is design-only; no code yet.
