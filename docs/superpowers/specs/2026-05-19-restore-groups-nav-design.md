# Restore Groups in admin nav

**Date:** 2026-05-19
**Owner:** David
**Status:** Design approved, ready for implementation plan

## Problem

The "Groups" feature (admin CRUD over `Organization` records, which own office leases, subscriptions, and member rosters) is unreachable from the navigation. Admins, GMs, and CMs have no menu path to `/organizations`, even though the entire backend is intact and working.

## Root cause

Commit `b6df9ae9` ("CRM Phase 8.1", 2026-05-15) replaced the top-level **"Members & Groups"** nav item with **"People (CRM)"** in `app/adapters/navigation/default.rb` for all three staff roles. The new People sub-nav has 5 chips — Members / Leads / Automations / Campaigns / Templates — none of which point at Groups. The old `members_groups_path` landing page and its `back_bar` references still exist, but nothing in the nav links to them anymore.

The `Organization` model, `Operator::OrganizationsController`, all its views (`index`, `show`, `edit`, `new`, `billing`, `leases`, `members`, `invoices`, `ltv`, …), routes at `/organizations`, API endpoints at `/api/v1/(admin/)?organizations`, `OrganizationPolicy`, and `MemberGroupPolicy` are all still in place and unchanged.

## Scope

In scope:
- Re-expose Groups in the staff nav for admin, GM, and CM roles.
- Update the existing nav specs to assert the new entry.

Out of scope (deliberate, leave for follow-up):
- Removing the orphaned `members_groups_path` landing page action, view, and `back_bar` references.
- Removing the orphaned `"Members & Groups"` icon entry from `_admin_nav.html.erb`.
- Any change to the `Organization` model, controllers, views, routes, or API.
- Any change to the React Native mobile repo (jellyswitch-mobile). The admin side renders inside a WKWebView, so the server-side nav change appears on Native automatically.

## Design

### Change 1 — Insert Groups in `Navigation::Default`

File: `app/adapters/navigation/default.rb`

In `admin_nav_items`, `general_manager_nav_items`, and `community_manager_nav_items`, add one line directly after the existing `items << {title: "People (CRM)", path: people_path}` entry:

```ruby
items << {title: "Groups", path: organizations_path}
```

For Community Manager, the nav currently does not include Offices & Leases, but the existing `MemberGroupPolicy` already permits CMs to view Groups (`MemberGroupPolicy#show?` allows admin / GM / CM). Restore Groups for all three staff roles to match the legacy behavior.

Members and logged-out users do not get Groups in their nav. This matches the existing policy.

### Change 2 — Icon mapping

File: `app/views/layouts/_admin_nav.html.erb`

The `nav_icons` hash currently maps `"Members & Groups" => "fas fa-users"`. Add a new key for the new label:

```erb
"Groups" => "fas fa-building",
```

The `fa-building` icon visually pairs with `"Offices & Leases" => "fas fa-building"` — fine, since Groups *are* the billing entity that owns office leases. The existing `"Members & Groups"` key stays for now (the orphaned landing-page `back_bar` partials still reference that title; harmless to leave until the follow-up cleanup).

### Change 3 — Nav specs

File: `spec/adapters/navigation/default_spec.rb` (existing — covers all three staff roles via a `shared_examples "People umbrella in nav"` block included by `:admin_nav_items`, `:general_manager_nav_items`, and `:community_manager_nav_items`).

Add a new shared example (or expand the existing block) that asserts:
- The role nav includes `"Groups"` immediately after `"People"`.
- The "Groups" entry's `:path` is `organizations_path`.

Also add a `spec/adapters/navigation/member_spec.rb` assertion that the member nav does **not** include "Groups", and (if there is a logged-out nav spec) the same for logged-out users.

If the spec for `community_manager_nav_items` needs a Pundit context that returns `community_manager?` as true, follow the pattern already used in `default_spec.rb` — do not introduce new test scaffolding.

## Verification

1. `bin/rails test spec/adapters/navigation` — all green, new assertions pass.
2. Local boot, sign in as admin on an Untethered subdomain. Confirm:
   - "Groups" appears in the navbar between "People (CRM)" and "Offices & Leases".
   - Clicking "Groups" lands on `/organizations` and shows the org list.
   - Create / edit / show / delete-with-no-active-lease all work (these already worked — just confirming nothing regressed).
3. Sign in as a GM, confirm Groups visible.
4. Sign in as a CM, confirm Groups visible.
5. Sign in as a regular member, confirm Groups **not** visible in the nav.
6. Open the admin UI in the iOS Untethered WebView build (or mobile-mode preview), confirm "Groups" appears in the hamburger menu list — no native-side change needed because the WebView renders the same `_admin_nav.html.erb`.

## Risk

Minimal. This is a one-line restoration of a nav entry that points at a fully-functioning, route-intact subsystem. The only behavior change is making an existing URL reachable from the menu again. No model, controller, view, route, policy, or API changes. The existing `OrganizationPolicy` already gates the underlying actions, so even if a user somehow navigated to `/organizations` without seeing the link, the policy would already protect them — restoring the link does not expand any user's effective permissions.

## Follow-up (separate PR)

Not part of this change, but should be cleaned up in a separate small PR once Groups is back in the nav:

- Delete `members_groups` action from `Operator::LandingController`.
- Delete `app/views/operator/landing/members_groups.html.erb`.
- Remove `get "/members_groups", to: "operator/landing#members_groups", as: :members_groups` from `config/routes.rb`.
- Update the five `back_bar` partials currently pointing at `members_groups_path` to point at the appropriate parent (most should point at `users_path` or `organizations_path`).
- Remove `"Members & Groups" => "fas fa-users"` from the `_admin_nav.html.erb` icons hash.
- Decide whether to delete `MemberGroupPolicy` + its test, or repurpose it. (Probably delete; nothing else references it once the landing page is gone.)
