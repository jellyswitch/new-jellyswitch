# 0031. Server-side conversions with first-touch attribution

Date: 2026-09-11

## Status

Accepted

## Context

Purchases already push a `purchase` dataLayer event so Google Ads can attribute
conversions (ADR-less, PR #735), but nothing is stored on our side. The Data
tab could not answer "how many signups and purchases came from Google Ads vs.
search vs. social vs. email?", and operators had no way to see what Jellyswitch
closed for them without staff. David (2026-09-11): "Attribution is paramount.
It would be nice to show spaces the lift they get from using Jellyswitch."

Ahoy already records every web visit (referrer, landing page, UTM params) and
links visits to a person on login, so the raw material exists. Two gaps: no
durable record of the conversion itself, and no per-person source.

## Decision

1. **`conversions` table** — one row per signup, lead (tour request, concierge
   chat), or purchase (membership, day pass, bundle, room reservation, office
   lease). Written by `Conversion.record` from every path: the web purchase
   hook (`ApplicationController#track_conversion`), the mobile API endpoints,
   the embed widgets, and admin member creation. It never raises into the
   caller. Rows are unique per `(subject, kind)` so retries and backfills are
   idempotent.
2. **First-touch attribution on the user** — `acquisition_*` columns stamped
   once by `Attribution::AssignFirstTouch`, walking from the first logged-in
   visit back to the earliest visit on the same persistent visitor cookie.
   `Attribution::Classifier` maps referrer / landing page / UTM / surface to a
   fixed channel vocabulary (paid_search, organic_search, social, email,
   referral, website, direct, app, …). Frozen once set; conversions snapshot it.
   First touch, not last touch, because the question operators ask is "which
   channel brought this person", and a single-touch model is explainable.
3. **`self_serve` + `surface` on the row** — whether the person acted for
   themselves (actor == user) and where (web / app / widget / admin). This is
   the "lift" story we can tell honestly: share of purchases and revenue that
   closed with no staff involved, and how many happened after hours. Backfilled
   history carries `surface: backfill` and is excluded from that share.
4. **`rails attribution:backfill`** reconstructs history from existing records
   so the report is useful from day one.
5. **Data › Conversions** (`Jellyswitch::AttributionReport`): funnel, by
   channel, by campaign, self-serve share, recent list, people-by-channel
   drill-down. Visits are brand-level (Ahoy landing host); everything else is
   location-scoped.

## Consequences

- ~70% of visits arrive with no referrer and most of the rest come from the
  operator's own WordPress site, so organic/social/email splits are only as
  good as link tagging. Follow-ups: UTM-tag campaign emails, pass UTM/click IDs
  through the widgets, decorate outbound links from the marketing sites.
- Mobile-app purchases have no Ahoy visit; they inherit the buyer's stored
  first touch or land in the `app` channel.
- A true counterfactual "lift" is not measurable; the page labels the metric
  as self-serve share, not lift.

## Addendum 2026-09-11 — site tracker ("one step before")

Ahoy only sees the visit to Jellyswitch, and the first touch there is almost
always the operator's own marketing site. David: "I'm looking for data one
step before the referral site." The concierge launcher already runs on every
page of those sites, so it now:

1. Captures the site's first touch once per browser (external referrer, UTM
   tags, ad click IDs, landing page; `localStorage`, 90 days) and appends it
   to the widget iframe and to every link that leaves for a Jellyswitch host
   at click time (`embed/_attribution_params.js.erb`). `Attribution::Classifier`
   reads `jsw_ref` as the referrer. No GTM work needed.
2. Sends one page-view beacon per page to `POST /embed/track/:subdomain`
   (`navigator.sendBeacon`, text/plain, no cookies, no IP stored). Sessions are
   `SiteVisit` rows (4h window) classified from their own referrer/UTM — the
   "Website Visits" tile and "Site visits" column on Data › Conversions.
   The tracker runs even when the chat bubble is disabled.
