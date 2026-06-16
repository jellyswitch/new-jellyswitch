# Day Pass Bundle — Operator UI Plan (Plan 5b)

> Use superpowers:subagent-driven-development. Controller actions + param permitting are TDD'd (request/controller specs, mirroring existing operator specs); ERB views verified structurally. Specs: `PATH="$HOME/.rbenv/shims:$PATH" bundle exec rspec <path>`. Worktree `~/Downloads/new-jellyswitch-bundles` (branch `feature/day-pass-bundles`).

**Goal:** Operators can (1) configure a day-pass type as an N-Pack with optional expiration (the CA hard-block is already enforced by the `DayPassType` validation from Plan 4), and (2) restore a burned pass to a member's bundle (auditable — `bundle.restore!`).

---

## Task 1: day-pass-type form — quantity + expiration

**Files:** `app/views/operator/day_pass_types/_form.html.erb`; `app/controllers/operator/day_pass_types_controller.rb` (permitted params); `spec/controllers/operator/day_pass_types_controller_spec.rb`.

- [ ] **Step 1 — Read** the controller's permitted-params method (find `params.require(:day_pass_type).permit(...)`) and the form partial.
- [ ] **Step 2 — Failing controller spec** (mirror the existing operator day_pass_types spec auth/setup):
  - Creating/updating a type with `quantity: 5` persists `quantity == 5`.
  - Setting `expires_after_days: 365` on a type whose location is **non-restricted** (e.g. `state: "NV"`) persists.
  - Setting `expires_after_days: 365` on a **CA** location is rejected (the model validation from Plan 4 fires; assert the record isn't updated / error is surfaced).
- [ ] **Step 3 — Implement.**
  - Permit `:quantity` and `:expires_after_days` in the day-pass-type params.
  - Form fields (match the partial's existing field style):
```erb
<div class="form-group">
  <%= form.label :quantity, "Number of passes (1 = single day pass; more = a bundle / N-Pack)" %>
  <%= form.number_field :quantity, class: "form-control", min: 1, step: 1 %>
</div>

<div class="form-group">
  <%= form.label :expires_after_days, "Passes expire this many days after purchase (leave blank = never expires)" %>
  <%= form.number_field :expires_after_days, class: "form-control", min: 1, step: 1, placeholder: "Never expires" %>
  <small class="form-text text-muted"><%= DayPassType::EXPIRATION_DISCLAIMER %></small>
</div>
```
  (The disclaimer is always shown; the validation hard-blocks it for restricted-state locations.)
- [ ] **Step 4 — Run green. Step 5 — Commit:**
```
git add app/views/operator/day_pass_types/_form.html.erb app/controllers/operator/day_pass_types_controller.rb spec/controllers/operator/day_pass_types_controller_spec.rb
git commit -m "feat: operator can set day-pass-type quantity + expiration (disclaimer + CA block)"
```

---

## Task 2: admin restore a pass to a member's bundle

Mirror the existing **`comp_days`** pattern (`resources :users do resources :comp_days, only: [:create], controller: "operator/comp_days" end` — the admin Day-Credit adjustment) for a parallel "restore a bundle pass" action.

**Files:** `config/routes.rb`; new `app/controllers/operator/day_pass_bundle_restores_controller.rb`; `app/views/operator/users/_day_passes.html.erb` (or the member page that lists passes) — add a bundles list + restore button; `spec/controllers/operator/day_pass_bundle_restores_controller_spec.rb`.

- [ ] **Step 1 — Read** `app/controllers/operator/comp_days_controller.rb` + its route + spec to mirror auth, the nested `:users` resource, and the redirect/flash pattern.
- [ ] **Step 2 — Failing controller spec:** as an admin, `POST /users/:user_id/day_pass_bundle_restores` with `{ day_pass_bundle_id:, reason: }` increments that bundle's `passes_remaining` by 1 and logs a `DayPassBundleRedemption` `kind: "admin_restore"` with `performed_by` = the admin. A non-admin / wrong-operator bundle is rejected.
- [ ] **Step 3 — Implement.**
  - Route: inside `resources :users, controller: "operator/users"`, add `resources :day_pass_bundle_restores, only: [:create], controller: "operator/day_pass_bundle_restores"`.
  - Controller `create`: authorize (mirror comp_days' authorization — admin/manager of the location), find the bundle scoped to the operator (and the member), call `bundle.restore!(by: current_user, reason: params[:reason])`, redirect back with a flash. Guard not-found / cross-tenant.
  - View: in the member's day-passes partial, render the member's `DayPassBundle`s (type name, `passes_remaining`, expires_at) each with a small "Restore a pass" form (POSTs the restore with an optional reason). Match the existing comp-day/admin-action button style.
- [ ] **Step 4 — Run green. Step 5 — Commit:**
```
git add config/routes.rb app/controllers/operator/day_pass_bundle_restores_controller.rb app/views/operator/users/ spec/controllers/operator/day_pass_bundle_restores_controller_spec.rb
git commit -m "feat: admin can restore a burned pass to a member's bundle (auditable)"
```

---

## Final gate (Plan 5b)
- [ ] `PATH="$HOME/.rbenv/shims:$PATH" bundle exec rspec spec/controllers/operator/day_pass_types_controller_spec.rb spec/controllers/operator/day_pass_bundle_restores_controller_spec.rb` green; existing operator day_pass_types spec green.
- [ ] Next: Plan 5c (Maestro staging flows), then staging run + on-site door-burn → merge.
