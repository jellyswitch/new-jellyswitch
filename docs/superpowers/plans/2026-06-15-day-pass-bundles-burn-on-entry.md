# Day Pass Bundle — Burn-on-Entry Plan (Plan 2)

> Use superpowers:subagent-driven-development + strict TDD. This touches BUILDING ACCESS — it gets an adversarial review before merge. Specs: `PATH="$HOME/.rbenv/shims:$PATH" bundle exec rspec <path>`.

**Goal:** A member with an active bundle but no other coverage can open the door, which burns one pass (mints today's `DayPass`) — **once per day**, **only if not otherwise covered**, from **both** the manual unlock and BLE auto-unlock paths.

**Design (see `CONTEXT.md` → Day Pass Bundle):**
- **Access gate awareness:** the door access gate currently denies a bundle-only user *before* any burn could happen. So `User#has_active_day_pass_bundle?(location)` is added to `user_can_access_building?` (and the `allowed_in?`/`has_building_access?` gates) so the door opens.
- **The burn is a side effect of the actual entry**, in a shared interactor `Billing::DayPassBundles::ConsumeOnEntry`, called from both unlock paths AFTER authorization. It is **idempotent per day** and **coverage-aware**:
  1. If the user already has a `DayPass` for today at this location → return (no burn). *(Re-entry rides on it; this is the once-per-day guarantee.)*
  2. If the user is otherwise covered today (active membership with days left / lease / reservation today) → return (no burn — they didn't need a bundle pass).
  3. Else if an **active** bundle exists at this location → mint `DayPass(day: today, location, day_pass_type: bundle.day_pass_type)` and `bundle.burn!(kind: :entry, performed_by: user, day_pass: minted)`.
- **Burn-on-grant, restore-on-failure:** the pass is spent when access is granted. If the physical unlock later fails (Kisi error), that's the admin-restore case (Plan 1's `restore!`) — we don't try to auto-reconcile the rare failure in v1. *(Discussion point — see below.)*

**DISCUSSION (resolve in review if needed):** burning at grant-time (not on confirmed Kisi success) keeps the manual + async-auto paths consistent and matches the "admin can add one back" decision. The alternative (burn only on confirmed unlock) would require threading the bundle through `KisiUnlockJob` and refunding on failure — more moving parts for a rare event. Recommendation: burn-on-grant + admin restore.

---

## Task 1: `User#has_active_day_pass_bundle?` + access-gate awareness

**Files:** `app/models/concerns/permissions.rb`, `app/controllers/concerns/api/v1/door_unlocking.rb`; tests in `spec/models/concerns/` + a request/controller spec.

- [ ] **Step 1 — Failing spec.** New `spec/models/day_pass_bundle_access_spec.rb`: a user with an active bundle at a location is `allowed_in?`/`user_can_access_building?` even with no membership/day-pass/lease/reservation; a user whose bundle is empty or expired is NOT; a bundle at a DIFFERENT location does NOT grant access here.
  - Reuse the door-access test harness: look at `test/controllers/api/v1/doors_controller_test.rb` and `spec/models/concerns/permissions*` for setup patterns.
- [ ] **Step 2 — Run, confirm fail.**
- [ ] **Step 3 — Implement.** Add to `app/models/concerns/permissions.rb`:
```ruby
  def has_active_day_pass_bundle?(location)
    return false unless location
    day_pass_bundles.active.where(location: location).exists?
  end
```
  (Add `has_many :day_pass_bundles` to `User` if not already present.) Then add `has_active_day_pass_bundle?(location)` as an OR-clause in BOTH `user_can_access_building?` (in `door_unlocking.rb`) and `allowed_in?` (permissions.rb). Match each method's existing style; place it alongside the day-pass check.
- [ ] **Step 4 — Run green. Step 5 — Commit.**

## Task 2: `ConsumeOnEntry` interactor (idempotent, coverage-aware burn)

**Files:** `app/interactors/billing/day_pass_bundles/consume_on_entry.rb`; `spec/interactors/billing/day_pass_bundles/consume_on_entry_spec.rb`. No Stripe.

- [ ] **Step 1 — Failing spec** covering the exact matrix:
```ruby
require "rails_helper"
RSpec.describe Billing::DayPassBundles::ConsumeOnEntry do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }
  let(:user) { create(:user, operator: operator) }
  let(:type) { create(:day_pass_type, operator: operator, location: location, quantity: 5) }
  def active_bundle(remaining: 5)
    DayPassBundle.create!(user: user, billable: user, operator: operator, location: location,
                          day_pass_type: type, quantity_purchased: 5, passes_remaining: remaining, purchased_at: Time.current)
  end
  def consume = described_class.call(user: user, location: location)

  it "burns one pass and mints today's DayPass when uncovered with an active bundle" do
    b = active_bundle
    expect { consume }.to change { b.reload.passes_remaining }.from(5).to(4)
                     .and change { user.day_passes.where(day: Date.current, location: location).count }.by(1)
    expect(b.redemptions.last.kind).to eq("entry")
    expect(b.redemptions.last.day_pass).to eq(user.day_passes.order(:id).last)
  end

  it "is idempotent — a second entry the same day does NOT burn again" do
    b = active_bundle
    consume
    expect { consume }.not_to change { b.reload.passes_remaining }
  end

  it "does NOT burn when the user already has a day pass for today" do
    b = active_bundle
    DayPass.create!(user: user, billable: user, operator: operator, location: location, day_pass_type: type, day: Date.current)
    expect { consume }.not_to change { b.reload.passes_remaining }
  end

  it "does NOT burn when there's no active bundle" do
    active_bundle(remaining: 0)
    expect { consume }.not_to change(DayPass, :count)
  end
end
```
  (If the user has an active subscription/lease/reservation today, also skip — add a coverage check mirroring `user_can_access_building?`. Add an example if the harness makes it cheap; otherwise rely on the day-pass-for-today idempotency, since those users never reach ConsumeOnEntry uncovered.)
- [ ] **Step 2 — Run, fail. Step 3 — Implement** the interactor: guard on existing DayPass-for-today (return), guard on other coverage (return), find `user.day_pass_bundles.active.where(location:).first`, then inside a transaction mint the DayPass and `bundle.burn!(kind: :entry, performed_by: user, day_pass: minted)`. Rescue `DayPassBundle::NoPassesRemaining` (race) → don't mint, return gracefully.
- [ ] **Step 4 — Run green. Step 5 — Commit.**

## Task 3: Wire `ConsumeOnEntry` into both unlock paths

**Files:** `app/controllers/concerns/api/v1/door_unlocking.rb` (`perform_unlock`), `app/controllers/api/v1/auto_unlocks_controller.rb` (`create`); request/controller specs.

- [ ] **Step 1 — Failing specs.** A bundle-only user hitting `POST /api/v1/doors/:id/unlock` and `POST /api/v1/door/auto_unlock` gets access AND burns exactly one pass; a second unlock the same day burns none; a member with a bundle burns none (membership covers them). Stub Kisi/the unlock side effects as the existing door specs do (`test/controllers/api/v1/doors_controller_test.rb`).
- [ ] **Step 2 — Run, fail. Step 3 — Implement:** call `Billing::DayPassBundles::ConsumeOnEntry.call(user:, location:)` right after the authorization passes — in `perform_unlock` (manual) and in `auto_unlocks_controller#create` before enqueuing `KisiUnlockJob`. Must not raise into the unlock flow (rescue/log).
- [ ] **Step 4 — Run green. Step 5 — Commit.**

## Final gate + adversarial review (before merge)
- [ ] Full suite for bundles + door/access specs green.
- [ ] **Adversarial review** (opus) of the complete burn-on-entry diff: double-burn under concurrency, the gate-says-yes-but-bundle-empty race, member/lease/reservation never burning, location scoping, the auto-path failure case (burned but Kisi failed → admin restore expected), and that no existing access path regressed.
