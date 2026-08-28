# Showcase + Office Inventory — V1 plan (grilled 2026-08-27)

Two new members of the embed widget family (see CONTEXT.md: Showcase, Office
Inventory; ADR 0027 for the inline-DOM transport). All decisions below were
resolved with David in the 2026-08-27 grilling session.

## Resolved decisions

1. **Names**: *Showcase* (curated good/better/best product tiers) and *Office
   Inventory* (live available-offices listing). The "VO widget" is a
   *link-out card* configuration of the Showcase, not a separate widget.
2. **Curation is lean**: products' existing `visible` flag gates both app and
   website ("visible in app = visible on website" — David). New per-product
   fields: `featured`, `display_order`, free-text `features` list. No separate
   Showcase composer page.
3. **What's-included = derived facts first, then free text.** System-derived
   bullets (meeting-room minutes, day limits, building-access level, bundle
   size) render verbatim, always-on, uneditable; operator free-text features
   follow. Enforced limits are never softened.
4. **Pinned-only at multi-location operators.** Every embed pins product type;
   multi-location operators must also pin location (prices live on location
   pages — verified against untethered.space's actual structure). Unpinned at
   multi-location renders a setup nudge with the per-location snippet lines,
   never a guessed or merged catalog. No side-by-side layout.
5. **CTA goes straight to checkout** (fewest hops to a transaction). The
   Concierge bubble on the same page is the questions path. Tier clicks record
   behavioral interest tags (`source: showcase`); no page-view tracking. Day
   Office rides the day-pass Showcase (it is a DayPassType).
6. **Post-purchase screen becomes product- and approval-aware** (upgrades the
   existing concierge checkout too): all four brands have
   `approval_required: true`, so buyers are created unapproved and must be told
   "the team reviews new members before first visit" — today's "You're in!"
   over-promises (approval is the building-access hard gate, ADR 0024). Also:
   show BOTH store links (Android is in the payload, currently unused), the
   pass date + location address/hours, membership next-steps.
7. **Office asking rate**: nullable `asking_rate_in_cents` on Office — the
   advertised monthly price for a vacant office; blank renders "Contact for
   pricing". The lease keeps owning the real negotiated price.
8. **Coming-available is a staff toggle, never derived**: an office whose lease
   is ending lists as "Available from <date>" ONLY when staff flip a per-office
   toggle — "they also might not be leaving" (David). Vacant-now offices list
   automatically. Inquiries record the office interest tag (feeding the office
   waitlist) and alert the location's team.
9. **Link-out cards**: per-location records (label, blurb, price line,
   outbound URL) rendering in a slot — among memberships, among day passes, or
   standalone (the /virtual-office page embeds the standalone slot). Sign-up
   happens on the external service; the click records interest first.
10. **Theming**: the existing shared embed-theme governs all four widgets; the
    inline transport inherits host typography by default (embed font = override).
11. **Settings consolidate into one "Website Widgets" area** (Concierge, Tour,
    Showcase, Office Inventory sections; shared Look & Feel on top). Office
    asking-rate/toggle live on the office edit form, not the widget page.

## Phases

- **Phase 1 — Showcase**: product fields migration (features[], featured,
  display_order on day_pass_types + plans), link-out cards table, script-embed
  route + inline renderer (namespaced CSS) + JSON-LD, pinned-only nudge,
  CTA → checkout with interest tags, post-purchase screen upgrade, Website
  Widgets settings consolidation with snippet generators.
- **Phase 2 — Office Inventory**: Office asking_rate + coming-available toggle
  (office form), inventory embed + office detail (single photo optional —
  Office has_one_attached :photo) + inquiry capture via the feedback chassis.

## Out of scope (deliberate)

Side-by-side multi-location layouts; modeling VO in-platform; anonymous
page-view analytics; multi-photo galleries; a Showcase composer page.

## Data bug found during grilling (fix separately, needs go)

Untethered Fulton's "2 day pass pack" ($59) has `quantity: 1` — the same
fake-bundle mis-sell class as the TLH pack-SKU incident (2026-08-10). Second
brand with this bug; strengthens the case for the deferred prevention guard
(validate pack-named SKUs carry quantity > 1, or a badge in the admin form).
