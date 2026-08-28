# The Showcase and Office Inventory render inline DOM, not iframes

The tour widget and Concierge are iframes (isolation, one-line-ish embeds, no
style bleed). The Showcase and Office Inventory deliberately break from that:
their embed is a `<script>` line that renders **real DOM into the host page**,
with **JSON-LD Product/Offer markup** carrying live prices (decided with David,
2026-08-27). The reason is the widgets' purpose: the operator's marketing pages
exist for SEO, and **content inside an iframe is not attributed to the page
that embeds it** — an iframe'd pricing table adds nothing to the page's
rankings. Product names, tiers, what's-included, and prices must be on-page
content; JSON-LD makes them eligible for price-rich results, which
hand-maintained coworking sites essentially never have. Inline rendering also
inherits the host site's typography by default — the embed-theme font becomes
an override, not a requirement. The costs are accepted and real: all widget CSS
must be namespaced (host pages run arbitrary WordPress/GoDaddy themes), style
bleed is possible in both directions, and there is no hard isolation boundary.
The transport is sticky — embed lines live on client sites indefinitely — so
this is not casually reversible. The tour widget and Concierge stay iframes:
a form and a conversation have no SEO value and benefit from isolation.

## Considered Options

- **Iframe, like the rest of the embed family** — rejected: zero SEO
  attribution defeats the widget's primary purpose; consistency of transport
  is worth less than the reason the widget exists.
- **JSON-LD only, visible content stays an iframe** — rejected: structured
  data describing content that isn't visibly on the page is cloaking-adjacent
  and risks manual action; markup must describe on-page content.
- **Static generation / copy-paste HTML into the CMS** — rejected: reinstates
  the price-drift problem the widgets exist to kill; the content must be
  served live from the catalog.
- **Server-side include / reverse proxy on the operator's site** — rejected:
  operators are on GoDaddy/WordPress hosting they barely control; a script
  tag is the only universally pasteable transport.
