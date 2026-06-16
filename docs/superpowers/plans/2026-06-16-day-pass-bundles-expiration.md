# Day Pass Bundle — Expiration + State Block Plan (Plan 4)

> Use superpowers:subagent-driven-development + strict TDD. Implements `docs/adr/0008-day-pass-bundle-expiration-opt-in-state-restricted.md`. Specs: `PATH="$HOME/.rbenv/shims:$PATH" bundle exec rspec <path>`.

**Goal:** Make bundle expiration an opt-in per-product setting that is **hard-blocked for products whose location is in an expiration-restricted state** (California to start), driven by an editable data list. Default = perpetual. Enforcement of an already-set `expires_at` (active scope + `burn!` guard) already exists from Plans 1–2; this adds the **config + the state guardrail + the purchase wiring**.

**NOT legal advice** — the disclaimer is presented; the operator + counsel own the decision. Fail-safe: unknown/blank location state → treated as restricted (no expiration).

---

## Task 1: `DayPassType.expires_after_days` + restricted-state guardrail

**Files:** migration; `app/models/day_pass_type.rb`, `app/models/location.rb`; tests in `spec/models/day_pass_type_spec.rb`, `spec/models/location_spec.rb` (or new).

- [ ] **Step 1 — Failing spec.** Append to `spec/models/day_pass_type_spec.rb`:
```ruby
  describe "expiration (ADR 0008)" do
    let(:operator) { create(:operator) }
    def type_in(state, expires_after_days: 365)
      loc = create(:location, operator: operator, state: state)
      build(:day_pass_type, operator: operator, location: loc, quantity: 5, expires_after_days: expires_after_days)
    end

    it "allows expiration for a non-restricted state" do
      expect(type_in("NV")).to be_valid
    end

    it "blocks expiration for California (abbrev or full)" do
      expect(type_in("CA")).not_to be_valid
      expect(type_in("California")).not_to be_valid
      expect(type_in("CA").tap(&:valid?).errors[:expires_after_days]).to be_present
    end

    it "blocks expiration when the location state is blank/unknown (fail-safe)" do
      expect(type_in("")).not_to be_valid
      expect(type_in(nil)).not_to be_valid
    end

    it "permits a perpetual (nil expires_after_days) product anywhere, including CA" do
      expect(type_in("CA", expires_after_days: nil)).to be_valid
    end
  end
```
And a `Location` spec: `create(:location, state: "CA").expiration_restricted?` is true; `"California"` true; `"NV"` false; `""`/`nil` true (fail-safe).

- [ ] **Step 2 — Run, fail.**

- [ ] **Step 3 — Migration:** `add_column :day_pass_types, :expires_after_days, :integer` (nullable; nil = perpetual). Migrate + `db:test:prepare`.

- [ ] **Step 4 — Implement.**
  - In `app/models/location.rb`:
```ruby
  # Editable data list — states where expiration on prepaid passes is restricted
  # or prohibited. Add states here as counsel advises; this is data, not logic.
  EXPIRATION_RESTRICTED_STATES = ["CA", "CALIFORNIA"].freeze

  # Fail-safe: unknown/blank state is treated as restricted (no expiration).
  def expiration_restricted?
    norm = state.to_s.strip.upcase
    return true if norm.blank?
    EXPIRATION_RESTRICTED_STATES.include?(norm)
  end
```
  - In `app/models/day_pass_type.rb`:
```ruby
  # Presented wherever expiration can be enabled. NOT legal advice.
  EXPIRATION_DISCLAIMER =
    "Expiration on prepaid passes is restricted or prohibited in many states, " \
    "including California (Civil Code §1749.5). It can't be enabled for this location.".freeze

  validate :expiration_allowed_for_location

  def expiration_allowed_for_location
    return if expires_after_days.blank?
    if location.nil? || location.expiration_restricted?
      errors.add(:expires_after_days, EXPIRATION_DISCLAIMER)
    end
  end
```

- [ ] **Step 5 — Run green. Step 6 — Commit:**
```
git add db/migrate db/schema.rb app/models/day_pass_type.rb app/models/location.rb spec/
git commit -m "feat: bundle expiration opt-in, hard-blocked in restricted states (ADR 0008)"
```

---

## Task 2: purchase wiring — bundle `expires_at` from the product's `expires_after_days`

**Files:** `app/interactors/billing/day_pass_bundles/save_bundle.rb`; `spec/interactors/billing/day_pass_bundles/create_bundle_spec.rb` (extend).

- [ ] **Step 1 — Failing spec** (extend the CreateBundle/SaveBundle spec):
```ruby
  it "sets expires_at from the product's expires_after_days when present" do
    loc = create(:location, operator: operator, state: "NV")
    t = create(:day_pass_type, operator: operator, location: loc, quantity: 5, expires_after_days: 30)
    ctx = described_class.call(params: { day_pass_type: t.id }, user_id: user.id, operator: operator, location: loc, out_of_band: true)
    expect(ctx).to be_success
    expect(ctx.day_pass_bundle.expires_at).to be_within(1.minute).of(Time.current + 30.days)
  end

  it "leaves expires_at nil (perpetual) when the product has no expiry" do
    # the existing default type has expires_after_days nil
    ctx = described_class.call(params: { day_pass_type: type.id }, user_id: user.id, operator: operator, location: location, out_of_band: true)
    expect(ctx.day_pass_bundle.expires_at).to be_nil
  end
```
(Adapt `described_class`/setup to the existing create_bundle spec; reuse its helpers.)

- [ ] **Step 2 — Run, fail. Step 3 — Implement:** in `SaveBundle`, when building the `DayPassBundle`, set `expires_at: day_pass_type.expires_after_days.present? ? Time.current + day_pass_type.expires_after_days.days : nil`. (Use `purchased_at` as the base if it's set just above — keep it consistent: `purchased_at + expires_after_days.days`.)
- [ ] **Step 4 — Run green. Step 5 — Commit:**
```
git add app/interactors/billing/day_pass_bundles/save_bundle.rb spec/interactors/billing/day_pass_bundles/create_bundle_spec.rb
git commit -m "feat: bundle purchase sets expires_at from the product's expiration policy"
```

---

## Final gate (Plan 4)
- [ ] `PATH="$HOME/.rbenv/shims:$PATH" bundle exec rspec spec/models/day_pass_type_spec.rb spec/models/location_spec.rb spec/interactors/billing/day_pass_bundles spec/models/day_pass_bundle_spec.rb` green.
- [ ] Enforcement note: an expired bundle already neither admits nor burns (Plan 1 `active` scope + Plan 2 `burn!`/`burn_locked!` expiry guard) — this plan only adds the policy + guardrail. The operator-facing disclaimer UI is Plan 5.
