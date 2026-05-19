# Restore Groups in admin nav — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Re-add a top-level "Groups" item to the admin / GM / CM nav that links to `/organizations`, so the existing Organization CRUD (offices, leases, billing) is reachable from the menu again.

**Architecture:** One-line insertion into each of the three staff nav builders in `Navigation::Default`, plus an icon entry in the admin nav partial. The `Organization` model, controller, views, routes, policies, and API are already intact — no backend work. RSpec covers nav assertions; admin = WebView on mobile, so the server-side change appears on Native automatically.

**Tech Stack:** Rails 7, RSpec, Pundit policies, Bootstrap admin nav partial.

**Spec:** [docs/superpowers/specs/2026-05-19-restore-groups-nav-design.md](../specs/2026-05-19-restore-groups-nav-design.md)

---

## Task 1: TDD — failing nav specs for Groups

**Files:**
- Modify: `spec/adapters/navigation/default_spec.rb`
- Modify: `spec/adapters/navigation/member_spec.rb`

- [ ] **Step 1: Add Groups assertions to the shared examples in `default_spec.rb`**

Edit `spec/adapters/navigation/default_spec.rb`. Inside the `shared_examples "People umbrella in nav"` block (currently lines 7–37), append these three new examples just before the final `end` of the block:

```ruby
    it "includes the Groups top-level item" do
      titles = nav.public_send(role_method).map { |i| i[:title] }
      expect(titles).to include("Groups")
    end

    it "links Groups at organizations_path" do
      groups = nav.public_send(role_method).find { |i| i[:title] == "Groups" }
      expect(groups[:path]).to eq("/organizations")
    end

    it "places Groups immediately after the People item" do
      titles = nav.public_send(role_method).map { |i| i[:title] }
      people_idx = titles.index { |t| t.to_s.start_with?("People") }
      expect(titles[people_idx + 1]).to eq("Groups")
    end
```

Use `start_with?("People")` for the position check because the current title is `"People (CRM)"` (see `app/adapters/navigation/default.rb:41`) — this keeps the spec robust if the label is renamed back to plain `"People"` later.

- [ ] **Step 2: Add a member-nav negative assertion to `member_spec.rb`**

Edit `spec/adapters/navigation/member_spec.rb`. Inside the `describe "#paths" do` block, in the `context "approved member with active subscription"` block (after the existing "Building Access" assertion around line 22), add:

```ruby
      it "does not include Groups" do
        titles = nav.paths.map { |item| item[:title] }
        expect(titles).not_to include("Groups")
      end
```

- [ ] **Step 3: Run the new specs and verify they FAIL**

```bash
bundle exec rspec spec/adapters/navigation/default_spec.rb spec/adapters/navigation/member_spec.rb
```

Expected: the three new `default_spec` examples × three role contexts = 9 failures (`expected ["Home", ...] to include "Groups"`). The new `member_spec` "does not include Groups" example should PASS (member nav doesn't have it yet — that's the point; member nav never gains it, so it's an anti-regression test).

If the existing People-umbrella specs are already failing in this repo, note that separately — do not fix them as part of this task.

- [ ] **Step 4: Do NOT commit yet** — failing tests stay uncommitted until the implementation lands in Task 2.

---

## Task 2: Implement nav adapter change

**Files:**
- Modify: `app/adapters/navigation/default.rb`

- [ ] **Step 1: Add Groups to `admin_nav_items`**

In `app/adapters/navigation/default.rb`, locate the existing line in `admin_nav_items` (around line 41):

```ruby
    items << {title: "People (CRM)", path: people_path}
```

Add immediately after it:

```ruby
    items << {title: "Groups", path: organizations_path}
```

- [ ] **Step 2: Add Groups to `general_manager_nav_items`**

In the same file, locate the matching line in `general_manager_nav_items` (around line 156):

```ruby
    items << {title: "People (CRM)", path: people_path}
```

Add immediately after it:

```ruby
    items << {title: "Groups", path: organizations_path}
```

- [ ] **Step 3: Add Groups to `community_manager_nav_items`**

In the same file, locate the matching line in `community_manager_nav_items` (around line 209):

```ruby
    items << {title: "People (CRM)", path: people_path}
```

Add immediately after it:

```ruby
    items << {title: "Groups", path: organizations_path}
```

- [ ] **Step 4: Run the nav specs and verify they now pass**

```bash
bundle exec rspec spec/adapters/navigation/default_spec.rb spec/adapters/navigation/member_spec.rb
```

Expected: all examples PASS, including the 9 new "includes Groups" / "links at organizations_path" / "after People" examples and the member-nav negative assertion.

If the existing People-umbrella specs were failing before Task 1 due to the `"People (CRM)"` label mismatch, they will still be failing — that is pre-existing and out of scope. Confirm the *new* specs pass.

- [ ] **Step 5: Commit**

```bash
git add spec/adapters/navigation/default_spec.rb spec/adapters/navigation/member_spec.rb app/adapters/navigation/default.rb
git commit -m "$(cat <<'EOF'
Restore Groups top-level nav item for admin/GM/CM

Adds {title: "Groups", path: organizations_path} immediately after the
People (CRM) item in all three staff nav builders. The Organization
CRUD (offices, leases, billing) at /organizations has been unreachable
from the menu since the CRM Phase 8.1 consolidation in b6df9ae9.

Spec: docs/superpowers/specs/2026-05-19-restore-groups-nav-design.md

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Icon mapping for the new Groups label

**Files:**
- Modify: `app/views/layouts/_admin_nav.html.erb:6`

- [ ] **Step 1: Add the Groups icon to the `nav_icons` hash**

In `app/views/layouts/_admin_nav.html.erb`, find the `nav_icons` hash (starts at line 2). Locate the existing entry at line 6:

```erb
    "Members & Groups" => "fas fa-users",
```

Add a new line directly after it:

```erb
    "Groups" => "fas fa-building",
```

The full hash region should now look like:

```erb
  nav_icons = {
    "Home" => "fas fa-home",
    "Building Access" => "fas fa-door-open",
    "People (CRM)" => "fas fa-users",
    "Members & Groups" => "fas fa-users",
    "Groups" => "fas fa-building",
    "Offices & Leases" => "fas fa-building",
    ...
```

Leave the existing `"Members & Groups"` key in place — it is still referenced by the orphaned `members_groups` landing page back-bar partials and will be cleaned up in a follow-up PR (see spec "Follow-up" section).

- [ ] **Step 2: Boot the app locally**

```bash
bin/rails s
```

In a separate shell or browser: sign in as an admin user on a local subdomain (e.g. `untethered.lvh.me:3000`).

- [ ] **Step 3: Smoke-check the nav (admin)**

In the browser:
1. Expand the admin navbar (collapse button on mobile, otherwise it's visible).
2. Confirm a **"Groups"** item appears with a building icon (`fa-building`), positioned between **"People (CRM)"** and **"Offices & Leases"**.
3. Click "Groups". Confirm:
   - URL is `/organizations`.
   - Page renders the organizations index without error.
   - Existing org rows (if any) are listed; "New Organization" / "New Group" button works.

- [ ] **Step 4: Smoke-check the nav (other roles)**

Repeat Step 3 for a General Manager user and a Community Manager user (use a CM/GM test account, or temporarily edit a user's `role` via `bin/rails console`).

Confirm:
- GM: Groups appears in nav, lands on `/organizations`.
- CM: Groups appears in nav, lands on `/organizations`.

- [ ] **Step 5: Smoke-check member nav (anti-regression)**

Sign in as a regular non-staff member. Confirm **no "Groups"** item appears in their nav.

- [ ] **Step 6: Commit**

```bash
git add app/views/layouts/_admin_nav.html.erb
git commit -m "$(cat <<'EOF'
Add Groups icon to admin nav icon map

Pairs with the restored "Groups" top-level nav item. Uses fa-building
since Groups (Organization records) own office leases. Keeps the legacy
"Members & Groups" key in place; the orphaned landing page will be
cleaned up in a follow-up PR.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Final verification + PR

**Files:**
- (no source changes)

- [ ] **Step 1: Full nav spec run**

```bash
bundle exec rspec spec/adapters/navigation/
```

Expected: all new "Groups" assertions PASS. (Any pre-existing failures in the People-umbrella examples are out of scope — note them in the PR description if present.)

- [ ] **Step 2: Targeted system test sanity-check**

Run the system test that exercises the Organizations index back-bar to confirm we haven't broken the legacy `members_groups_path` reference:

```bash
bin/rails test test/system/delete_group_test.rb
```

Expected: all four tests PASS (the existing tests cover Organization show + delete flows from `/organizations`, which is exactly the destination of the new nav item).

If the system test runner is slow / flaky, skip this step locally and rely on CI.

- [ ] **Step 3: Push the branch and open a PR**

```bash
git push -u origin "$(git branch --show-current)"
```

Then:

```bash
gh pr create --title "Restore Groups top-level nav item" --body "$(cat <<'EOF'
## Summary

- Re-adds a top-level **Groups** nav item to admin / GM / CM nav, linking to `/organizations`.
- The Organization CRUD (offices, leases, billing) backend has been intact the whole time — it was only the nav entry that was lost when CRM Phase 8.1 (b6df9ae9) replaced "Members & Groups" with "People (CRM)".
- Icon: `fa-building` (Groups own office leases).
- Mobile (Native): no change needed — admin UI renders inside WKWebView.

## Test plan

- [x] `bundle exec rspec spec/adapters/navigation/` — Groups assertions pass for admin / GM / CM, member nav anti-regression passes
- [x] `bin/rails test test/system/delete_group_test.rb` — existing Organization delete flow still works
- [x] Local smoke: admin sees Groups in nav between People (CRM) and Offices & Leases, click lands on `/organizations`
- [x] Local smoke: GM and CM see Groups in nav
- [x] Local smoke: regular member does NOT see Groups in nav

## Spec

docs/superpowers/specs/2026-05-19-restore-groups-nav-design.md

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 4: Confirm CI passes**

Wait for GitHub Actions to run. Per the project's CI structure ([reference_ci_three_jobs.md](../../../../../.claude/projects/-Users-DavidOrr-Downloads-new-jellyswitch/memory/reference_ci_three_jobs.md)), three jobs run sequentially: Minitest unit → RSpec → Minitest system. Watch for green on the RSpec job in particular.

If CI fails on a job unrelated to nav (e.g. a flaky test in another area per [project_test_suite_cleanup_2026_05.md](../../../../../.claude/projects/-Users-DavidOrr-Downloads-new-jellyswitch/memory/project_test_suite_cleanup_2026_05.md)), call it out in the PR but do not block the merge — the user's deploy workflow ships red builds too ([feedback_deploy.md](../../../../../.claude/projects/-Users-DavidOrr-Downloads-new-jellyswitch/memory/feedback_deploy.md)).
