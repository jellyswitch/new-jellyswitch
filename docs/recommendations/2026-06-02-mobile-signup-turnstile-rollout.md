# Turnstile on mobile/API member signup — phased rollout

**Date:** 2026-06-02
**Endpoint:** `POST /api/v1/auth/signup` → `Api::V1::AuthController#signup`
**Follow-up to:** PR #479 (Turnstile on web operator signup + `Turnstile::Verifier` structured logging)

## Why this is phased (the production-breakage trap)

In production `TURNSTILE_SECRET` is set, so `Turnstile::Verifier.call(...)` actually
hits Cloudflare. If the server hard-requires a `cf-turnstile-response` token before
the deployed mobile apps send one, **every** mobile signup fails with
`missing-input-response`. So we cannot do a naive server-side enforcement — it must
be a coordinated, backward-compatible rollout.

```
Phase 1 (DONE, this PR)   Server: verify IF token present, never hard-fail on absent. Log adoption.
Phase 2 (mobile work)     Client: add Turnstile widget to RN signup, send token. Ship 3 brands (build + OTA).
Phase 3 (strict cutover)  Server: require a valid token — gated by app-version header, not a hard cutover.
```

---

## Phase 1 — Server, lenient (SHIPPED in this PR)

`Api::V1::AuthController#signup`:
- **Honeypot** `_hp`: silent generic 422 if filled (parity with web form / tour widget).
- **Lenient Turnstile**: verify **only when** `params["cf-turnstile-response"]` is present.
  - Present + valid → proceed.
  - Present + invalid → `422 Captcha verification failed`.
  - **Absent → proceed untouched** (old store builds keep working).
- Every verification logs one structured line via `Turnstile::Verifier(context: "mobile_signup")`:
  `{event:"turnstile_verification", context:"mobile_signup", outcome:, error_codes:, remote_ip:}`.

Also shipped (independent defense-in-depth):
- **Rack::Attack** `signup/ip` throttle, 5/min/IP, covering `POST /onboarding/create_user`
  (web operator signup) and `POST /api/v1/auth/signup` (mobile member signup).

Tests: `test/controllers/api/v1/auth_controller_test.rb` (lenient pass-through, valid token,
failing token, `mobile_signup` context, honeypot, throttle), plus a `mobile_signup`
logging case in `test/services/turnstile/verifier_test.rb`.

### Watch adoption before flipping to strict

Tail prod logs for the new context and confirm the token-carrying share climbs as the
new build rolls out:

```
# share of mobile signups that carried a token (passes + present-but-invalid)
heroku logs --tail | grep '"context":"mobile_signup"'
```

- `outcome:"pass"` and `outcome:"fail"` with bot-ish codes (`missing-input-response`,
  `invalid-input-response`) = clients that ARE sending tokens.
- **Absence of a log line for a signup** = an old client (untokened) still in the wild.
  (Untokened signups are intentionally NOT logged, since the Verifier is never called —
  so measure adoption as `count(mobile_signup log lines) / count(successful signups)`.)
- Watch for `invalid-input-secret` → our config is broken, would block everyone in Phase 3.

Only proceed to Phase 3 once the token-carrying share is high (≈ the floor of users who
won't update). Old-build users who never update will be handled by the app-version gate.

---

## Phase 2 — Mobile client (jellyswitch-mobile repo)

React Native has no native `cf-turnstile` div, so the widget runs in a WebView.

### Options investigated
| Option | Notes |
|---|---|
| **`react-native-turnstile` / `@cloudflare/...` libs** | Thin WebView wrappers; small, but verify upkeep & RN 0.81 / Expo compatibility before adding a dep. |
| **Hand-rolled WebView challenge** (recommended) | Load a tiny HTML page hosting the Turnstile script in `react-native-webview`; postMessage the token back. Zero new native deps, full control over sitekey-per-brand and invisible/managed mode. |
| **Invisible / managed widget** | Best UX (no checkbox for most users). Use managed mode so only suspicious sessions see interaction. Implement on top of whichever wrapper above. |

### Checklist
- [ ] Obtain/confirm a Turnstile **sitekey per brand** (the secret is shared server-side via
      `TURNSTILE_SECRET`; sitekeys are public and can be per-brand). Brand keys are hyphenated:
      `untethered`, `cowork-tahoe`, `choose-folsom`.
- [ ] Build a `<TurnstileWidget brand=... onToken=...>` WebView component (managed/invisible mode).
- [ ] Wire it into `SignupScreen` — obtain a token on submit, include it in the signup POST body
      as `cf-turnstile-response` (the exact param the server reads).
- [ ] Send an **app-version header** on the signup request (e.g. `X-App-Version` /
      `X-Client-Version`) so Phase 3 can gate strict enforcement on builds known to send a token.
      Pick a header now and ship it in the same build as the widget.
- [ ] Handle widget failure gracefully (network/timeout) — don't hard-block the user in the
      client; let the server decide (Phase 1 server is lenient, so a missing token still works).
- [ ] Test on all 3 brands in light AND dark mode (WebView background theming).
- [ ] **Ship to all 3 brands**: store build (sitekey is baked per brand) **+ OTA** for the JS.
      Note: OTA only reaches builds compiled with the EAS Update config — see
      `reference_eas_update_ota.md`. A WebView/native-dep change needs a fresh store build first.
- [ ] Run Maestro after the UI change (`tests/maestro/run_all.sh`).

---

## Phase 3 — Server, strict (gated, NOT a hard cutover)

Only after Phase-1 logs confirm broad adoption.

- Read the app-version header set in Phase 2. **Require a valid token only for builds known to
  send one** (version ≥ the Turnstile build). Builds below that threshold (or with no version
  header = ancient) stay lenient, so we never break a user who hasn't updated.
- Pseudocode:
  ```ruby
  client_version = request.headers["X-App-Version"]
  turnstile_required = client_version.present? &&
                       Gem::Version.new(client_version) >= TURNSTILE_MIN_VERSION
  token = params["cf-turnstile-response"]
  if turnstile_required && token.blank?
    return render_error("Captcha required. Please update the app.", status: :unprocessable_entity)
  end
  # ... existing present-token verification stays the same ...
  ```
- Add a test: version ≥ threshold + no token → 422; version < threshold + no token → still creates.
- Consider a forced-update nudge for pre-Turnstile builds so the long tail eventually drains and
  the version gate can be removed.

---

## Files (Phase 1)
- `app/controllers/api/v1/auth_controller.rb` — honeypot + lenient verify.
- `config/initializers/rack_attack.rb` — `signup/ip` throttle.
- `test/controllers/api/v1/auth_controller_test.rb`, `test/services/turnstile/verifier_test.rb`.

Run tests: `export PATH="$HOME/.rbenv/shims:$PATH"; RBENV_VERSION=3.3.10 bundle exec rails test <files>`.
Repo disallows squash merges — use `gh pr merge --merge`.
