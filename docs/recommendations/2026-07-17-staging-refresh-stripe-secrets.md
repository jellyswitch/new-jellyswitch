# Staging refresh: scrub live Stripe secrets after every pg:copy

**TL;DR — after every prod → staging database copy, run:**

```sh
heroku run rake staging:scrub_stripe_secrets -a jellyswitch-staging
```

The task refuses to run anywhere `STRIPE_SECRET_KEY` isn't a test key, so it
cannot damage production.

## Why

When an operator clicks "Connect Stripe", the OAuth token exchange
(`Operators::FinishStripeConnect`) stores three values on their `Operator` and
`Location` rows, and all three are **live-mode credentials** for the connected
Stripe account:

| column | what it actually is |
|---|---|
| `stripe_access_token` | a live **secret key** (`sk_live_…`) for the connected account |
| `stripe_refresh_token` | can mint new access tokens |
| `stripe_publishable_key` | the connected account's live publishable key |

`heroku pg:copy` from prod carries these into staging verbatim, so every
staging refresh leaves live credentials sitting in a test database.

App code never uses them for API calls — every Stripe request uses the
platform key from env config plus a `Stripe-Account` header, and since
[PR #656](https://github.com/jellyswitch/new-jellyswitch/pull/656) the
publishable key served to clients is env-based too (`Location#stripe_publishable_key`
overrides the column). So scrubbing changes nothing functionally on staging;
it just removes live secrets from a non-production environment.

`stripe_user_id` (the `acct_…` id) is **not** scrubbed: it isn't a secret and
staging's test-mode Stripe calls still need it.

## History

Before PR #656, `GET /api/v1/stripe_config` served the copied
`stripe_publishable_key` column directly, so staging handed mobile clients a
`pk_live_` key while the server used test-mode secret keys. Clients minted
live tokens the server couldn't consume → "Cannot update payment method" in
`Billing::Payment::UpdateUserPayment`, making card entry untestable on
staging. That's fixed at the code level; the scrub is defense-in-depth for
the credentials themselves.

## Other prod data that survives a copy (not scrubbed yet, be aware)

- `kisi_api_key` on operators/locations — staging flows can operate **real
  door hardware**.
- Users' push tokens — staging can send push notifications to members' real
  devices.
- Members' real email addresses — anything on staging that sends mail,
  mails real people.

If any of these bites, extend `staging:scrub_stripe_secrets` into a general
`staging:scrub`.
