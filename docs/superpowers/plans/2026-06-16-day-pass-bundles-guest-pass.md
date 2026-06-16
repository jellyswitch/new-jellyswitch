# Day Pass Bundle — Guest Pass Plan (Plan 3)

> Use superpowers:subagent-driven-development + strict TDD. Specs: `PATH="$HOME/.rbenv/shims:$PATH" bundle exec rspec <path>`.

**Goal:** Let a bundle holder spend one pass on a **self-attested guest** (name only, no account) — the dedicated guest-redemption surface decided in the grill (see `CONTEXT.md` → Day Pass Bundle "Guest pass"). The redemption ledger already supports `kind: guest` + `guest_name`; this adds the action + the member API. (Mobile UI is Plan 5.)

**Design:**
- A guest check-in is an **explicit, deliberate burn** — NOT period-gated like the holder's auto-burn. Each call spends exactly one pass (two guests = two taps = two burns). It's the only way one account spends >1 pass in a period.
- No `Checkin` row, no `DayPass` minted (the guest never authenticates; the host opens the door). The burn + the `guest` redemption (with `guest_name`) is the whole record.

---

## Task 1: `Billing::DayPassBundles::CheckInGuest` interactor

**Files:** `app/interactors/billing/day_pass_bundles/check_in_guest.rb`; `spec/interactors/billing/day_pass_bundles/check_in_guest_spec.rb`.

Given `bundle:` + `performed_by:` (the holder) + optional `guest_name:`, burn one pass as a `guest` redemption. Fail cleanly if the bundle is inactive/empty.

- [ ] **Step 1 — Failing spec:**
```ruby
require "rails_helper"
RSpec.describe Billing::DayPassBundles::CheckInGuest do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }
  let(:user) { create(:user, operator: operator) }
  let(:type) { create(:day_pass_type, operator: operator, location: location, quantity: 5) }
  def bundle(remaining: 5, expires_at: nil)
    DayPassBundle.create!(user: user, billable: user, operator: operator, location: location,
                          day_pass_type: type, quantity_purchased: 5, passes_remaining: remaining,
                          expires_at: expires_at, purchased_at: Time.current)
  end

  it "burns one pass as a guest redemption with the guest name" do
    b = bundle
    expect { described_class.call(bundle: b, performed_by: user, guest_name: "Sam") }
      .to change { b.reload.passes_remaining }.from(5).to(4)
    r = b.redemptions.order(:id).last
    expect(r.kind).to eq("guest")
    expect(r.guest_name).to eq("Sam")
    expect(r.performed_by).to eq(user)
    expect(r.day_pass).to be_nil
  end

  it "fails when the bundle has no passes left" do
    b = bundle(remaining: 0)
    ctx = described_class.call(bundle: b, performed_by: user, guest_name: "Sam")
    expect(ctx).to be_failure
    expect(b.reload.passes_remaining).to eq(0)
  end

  it "fails when the bundle is expired" do
    b = bundle(expires_at: 1.day.ago)
    ctx = described_class.call(bundle: b, performed_by: user, guest_name: "Sam")
    expect(ctx).to be_failure
  end

  it "allows a blank guest name" do
    b = bundle
    ctx = described_class.call(bundle: b, performed_by: user)
    expect(ctx).to be_success
    expect(b.reload.passes_remaining).to eq(4)
  end
end
```

- [ ] **Step 2 — Run, fail. Step 3 — Implement** (`include Interactor`): `context.bundle.burn!(kind: :guest, performed_by: context.performed_by, guest_name: context.guest_name)`, rescuing `DayPassBundle::NoPassesRemaining` → `context.fail!(message: "No passes remaining in this bundle.")`. Set `context.redemption` to the created redemption. (Note: `burn!` already guards `expired?` and `passes_remaining <= 0`, so both failure cases route through the rescue.)
- [ ] **Step 4 — Run green. Step 5 — Commit:**
```
git add app/interactors/billing/day_pass_bundles/check_in_guest.rb spec/interactors/billing/day_pass_bundles/check_in_guest_spec.rb
git commit -m "feat: CheckInGuest burns one bundle pass as a self-attested guest redemption"
```

---

## Task 2: Member API — list my bundles + check in a guest

**Files:** new `app/controllers/api/v1/day_pass_bundles_controller.rb`, `config/routes.rb`; `spec/requests/api/v1/day_pass_bundles_spec.rb`.

Read an existing `Api::V1` controller (e.g. `day_passes_controller.rb`) for the auth pattern (`current_api_user`, `current_location`, tenant) and mirror it. Read `config/routes.rb` to place routes alongside the existing `day_passes` routes.

- [ ] **Step 1 — Failing request spec.** Mirror the auth-header helper used by `spec/requests/api/v1/day_pass_bundle_purchase_spec.rb` (built in Plan 1).
  - `GET /api/v1/day_pass_bundles` → returns the current user's **active** bundles as `[{ id, day_pass_type_name, location_id, passes_remaining, expires_at }]` (ordered, only active).
  - `POST /api/v1/day_pass_bundles/:id/check_in_guest` with `{ guest_name: "Sam" }` → 200/201, burns one pass on THAT bundle (owned by the current user), returns `{ id, passes_remaining }`. A bundle the user doesn't own → 404. An empty bundle → 422 with an error message.

- [ ] **Step 2 — Run, fail. Step 3 — Implement:**
  - Routes: `resources :day_pass_bundles, only: [:index] do; member { post :check_in_guest }; end` inside the existing `api/v1` namespace (match its structure).
  - `index`: `current_api_user.day_pass_bundles.active` (tenant-scoped) → JSON above.
  - `check_in_guest`: load `current_api_user.day_pass_bundles.find(params[:id])` (scopes ownership; 404 if not theirs), call `Billing::DayPassBundles::CheckInGuest.call(bundle:, performed_by: current_api_user, guest_name: params[:guest_name])`; render `{ id:, passes_remaining: }` on success, `render_error(...)`/422 on failure.
- [ ] **Step 4 — Run green. Step 5 — Commit:**
```
git add app/controllers/api/v1/day_pass_bundles_controller.rb config/routes.rb spec/requests/api/v1/day_pass_bundles_spec.rb
git commit -m "feat: member API to list day-pass bundles + check in a guest"
```

---

## Final gate (Plan 3)
- [ ] `PATH="$HOME/.rbenv/shims:$PATH" bundle exec rspec spec/interactors/billing/day_pass_bundles spec/requests/api/v1/day_pass_bundles_spec.rb` green.
- [ ] Still no merge — Plan 4 (expiration enforcement) + Plan 5 (UI) remain; merge gated on the staging Stripe + door-burn check.
