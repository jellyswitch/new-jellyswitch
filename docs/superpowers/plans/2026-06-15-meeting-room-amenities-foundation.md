# Meeting-Room Amenities — Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let an operator give each meeting-room amenity a member rate and a non-member rate, treat free (0/0) amenities as descriptive features and priced ones as orderable add-ons, expose that split to the API, and make reservation charging depend purely on `billing_state` (not a hardcoded subdomain).

**Architecture:** Behavior is derived from the amenity's two existing rate columns (`price` = non-member, `membership_price` = member) — no new `kind` column (see `docs/adr/0007-amenity-behavior-derived-from-rate.md`). The admin form drops the Regular/Membership radio for two always-visible labeled rate fields. The API gains `add_ons` and `amenity_features` keys additively (existing `amenities`/`features` keys are left untouched so the current mobile app keeps working). The Southlake subdomain hardcode in the charging gate is removed in favor of `billing_state == "production"`.

**Tech Stack:** Rails, RSpec + FactoryBot (the amenities domain is already RSpec — see `spec/models/amenity_spec.rb`), Cocoon-style nested form fields, ERB.

**Scope note:** This is the *foundation* plan. Three follow-on plans are intentionally out of scope here: (2) mobile display + add-on selection UI, (3) wiring `amenity_ids` into the API booking/charge path (`Api::V1::ReservationsController#create` → `Billing::Reservations::CreateRoomReservation`), and (4) the synthetic demo-operator seed. This plan produces working, testable software on its own: operators can enter member/non-member rates, the feature/add-on rule is enforced and tested, the API exposes the data, and charging is `billing_state`-driven.

**Run all specs with:** `bundle exec rspec <path>`

---

## Pre-flight (do once, before Task 1)

- [ ] **Check Southlake's current billing_state** — removing the hardcode changes their behavior if they are a live charging customer still flagged `demo`.

Run:
```bash
bin/rails runner 'o = Operator.find_by(subdomain: "southlakecoworking"); puts o ? "southlake billing_state=#{o.billing_state}" : "southlake operator not found"'
```
Expected: prints the current state. If it prints `billing_state=demo` **and** Southlake is a live customer who should be charged, run the flip below so removing the hardcode doesn't silently stop their billing. If it already prints `production` (or the operator isn't found), no action — proceed to Task 1.

- [ ] **If needed, flip Southlake to production:**
```bash
bin/rails runner 'o = Operator.find_by(subdomain: "southlakecoworking"); o&.update!(billing_state: "production"); puts "now #{o&.billing_state}"'
```

---

## Task 1: Charging gate depends on billing_state only

Remove the `|| operator.subdomain == "southlakecoworking"` clause from both charging predicates so the gate is purely `billing_state`-driven.

**Files:**
- Modify: `app/models/concerns/permissions.rb` (`should_charge_for_reservation?`, `should_charge_for_room?`)
- Test: `spec/models/concerns/permissions_charging_spec.rb` (create)

- [ ] **Step 1: Write the failing test**

Create `spec/models/concerns/permissions_charging_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe "charging gate (Permissions)" do
  def non_member_in(operator)
    location = create(:location, operator: operator)
    user = create(:user, operator: operator)
    [user, location]
  end

  it "charges a non-member at a production operator" do
    user, location = non_member_in(create(:operator, billing_state: "production"))
    expect(user.should_charge_for_reservation?(location)).to be(true)
  end

  it "does NOT charge anyone at a demo operator" do
    user, location = non_member_in(create(:operator, billing_state: "demo"))
    expect(user.should_charge_for_reservation?(location)).to be(false)
  end

  it "no longer special-cases the southlakecoworking subdomain" do
    # A demo operator that happens to use that subdomain must behave like any
    # other demo operator now — the hardcode is gone.
    operator = create(:operator, billing_state: "demo", subdomain: "southlakecoworking")
    user, location = non_member_in(operator)
    expect(user.should_charge_for_reservation?(location)).to be(false)
  end

  it "charges a non-member for a paid room only when production" do
    paid_room = ->(op) { create(:room, operator: op, location: create(:location, operator: op), hourly_rate_in_cents: 5000, rentable: true) }
    prod = create(:operator, billing_state: "production")
    demo = create(:operator, billing_state: "demo")
    expect(create(:user, operator: prod).should_charge_for_room?(paid_room.call(prod))).to be(true)
    expect(create(:user, operator: demo).should_charge_for_room?(paid_room.call(demo))).to be(false)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/models/concerns/permissions_charging_spec.rb`
Expected: the "southlakecoworking" example FAILS (returns `true` because the hardcode still fires for that subdomain).

- [ ] **Step 3: Remove the hardcode**

In `app/models/concerns/permissions.rb`, change `should_charge_for_reservation?`:
```ruby
  def should_charge_for_reservation?(location, day = Time.current)
    if operator.production?
      !(member?(location) || has_purchased_day_pass?(day) || has_active_lease? || admin_of_location?(location) || superadmin? || general_manager_of_location?(location) || community_manager_of_location?(location))
    else
      false
    end
  end
```

And `should_charge_for_room?`:
```ruby
  def should_charge_for_room?(room, day = Time.current)
    return false unless room.hourly_rate_in_cents.to_i > 0
    location = room.location
    if operator.production?
      !(member?(location) || has_active_lease? || admin_of_location?(location) || superadmin? || general_manager_of_location?(location) || community_manager_of_location?(location))
```
(Leave the rest of `should_charge_for_room?` below this line unchanged.)

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/models/concerns/permissions_charging_spec.rb`
Expected: PASS (4 examples).

- [ ] **Step 5: Commit**
```bash
git add app/models/concerns/permissions.rb spec/models/concerns/permissions_charging_spec.rb
git commit -m "fix: charging gate keys on billing_state, drop southlakecoworking hardcode"
```

---

## Task 2: Amenity feature/add-on behavior (derived from rate)

Add predicates and scopes so "feature vs add-on" is computed from the rates, never stored.

**Files:**
- Modify: `app/models/amenity.rb`
- Test: `spec/models/amenity_spec.rb` (append)

- [ ] **Step 1: Write the failing test**

Append to `spec/models/amenity_spec.rb` (inside the top-level `RSpec.describe Amenity do ... end` block):
```ruby
  describe "feature vs add-on (derived from rate)" do
    let(:room) { create(:room) }

    it "is a feature when both rates are zero" do
      a = create(:amenity, room: room, name: "Whiteboard", price: 0, membership_price: 0)
      expect(a.feature?).to be(true)
      expect(a.orderable?).to be(false)
    end

    it "is an orderable add-on when any rate is positive" do
      paid = create(:amenity, room: room, name: "Catering", price: 50, membership_price: 35)
      free_for_members = create(:amenity, room: room, name: "Parking", price: 20, membership_price: 0)
      expect(paid.orderable?).to be(true)
      expect(free_for_members.orderable?).to be(true)
      expect(paid.feature?).to be(false)
    end

    it "scopes partition the association" do
      create(:amenity, room: room, name: "Monitor", price: 0, membership_price: 0)
      create(:amenity, room: room, name: "Catering", price: 50, membership_price: 35)
      expect(room.amenities.features.pluck(:name)).to eq(["Monitor"])
      expect(room.amenities.add_ons.pluck(:name)).to eq(["Catering"])
    end
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/models/amenity_spec.rb -e "feature vs add-on"`
Expected: FAIL with `NoMethodError: undefined method 'feature?'`.

- [ ] **Step 3: Implement on the model**

In `app/models/amenity.rb`, add inside the class (after the validations):
```ruby
  # An amenity's behavior is derived from its rates, not a stored type
  # (see docs/adr/0007-amenity-behavior-derived-from-rate.md):
  #   both rates 0  -> a passive room feature (informational, never charged)
  #   any rate > 0  -> an orderable add-on (selectable per reservation, charged)
  scope :add_ons, -> { where("price > 0 OR membership_price > 0") }
  scope :features, -> { where(price: 0, membership_price: 0) }

  def orderable?
    [price.to_f, membership_price.to_f].max > 0
  end

  def feature?
    !orderable?
  end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/models/amenity_spec.rb`
Expected: PASS (existing + 3 new examples).

- [ ] **Step 5: Commit**
```bash
git add app/models/amenity.rb spec/models/amenity_spec.rb
git commit -m "feat: amenity feature/add-on behavior derived from rate"
```

---

## Task 3: Room serialization helpers + API exposure

Put the serialization on the model (unit-testable without HTTP), then call it from the API. Add new keys **additively** — leave the existing `amenities` and `features` keys untouched so the current mobile app is unaffected.

**Files:**
- Modify: `app/models/room.rb`
- Modify: `app/controllers/api/v1/rooms_controller.rb` (every `amenities: ...pluck(:name)` site)
- Test: `spec/models/room_spec.rb` (append; create if absent)

- [ ] **Step 1: Write the failing test**

Append to `spec/models/room_spec.rb` (inside `RSpec.describe Room do ... end`; if the file does not exist, create it with `require "rails_helper"` and that describe block):
```ruby
  describe "#amenity_add_ons / #amenity_feature_names" do
    let(:room) { create(:room) }

    before do
      create(:amenity, room: room, name: "Whiteboard", price: 0, membership_price: 0)
      create(:amenity, room: room, name: "Catering", price: 50, membership_price: 35)
    end

    it "returns priced add-ons as structured hashes in cents" do
      expect(room.reload.amenity_add_ons).to eq([
        { id: room.amenities.find_by(name: "Catering").id,
          name: "Catering",
          non_member_rate_cents: 5000,
          member_rate_cents: 3500 },
      ])
    end

    it "returns free amenities as plain feature names" do
      expect(room.reload.amenity_feature_names).to eq(["Whiteboard"])
    end
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/models/room_spec.rb -e "amenity_add_ons"`
Expected: FAIL with `NoMethodError: undefined method 'amenity_add_ons'`.

- [ ] **Step 3: Implement on the model**

In `app/models/room.rb`, add inside the class (near the other instance methods, e.g. after `has_whiteboard?`):
```ruby
  # API serialization for the member-facing room card. Free amenities render as
  # informational chips (names only); priced amenities render as selectable
  # add-ons carrying both rates in cents. Rates are stored as float dollars.
  def amenity_add_ons
    amenities.add_ons.map do |a|
      {
        id: a.id,
        name: a.name,
        non_member_rate_cents: (a.price.to_f * 100).round,
        member_rate_cents: (a.membership_price.to_f * 100).round,
      }
    end
  end

  def amenity_feature_names
    amenities.features.map(&:name)
  end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/models/room_spec.rb -e "amenity"`
Expected: PASS (2 examples).

- [ ] **Step 5: Wire into the API (additive keys)**

In `app/controllers/api/v1/rooms_controller.rb`, find every line that reads `amenities: room.amenities.pluck(:name)` or `amenities: r.amenities.pluck(:name)` (there are 3 — confirm with `grep -n "amenities:.*pluck(:name)" app/controllers/api/v1/rooms_controller.rb`). Immediately **after** each such line, add the two new keys, matching the local variable name (`room` or `r`). For the `room`-named sites:
```ruby
          amenities: room.amenities.pluck(:name),
          add_ons: room.amenity_add_ons,
          amenity_features: room.amenity_feature_names,
```
For the `r`-named site inside the `reserve_now` lambda:
```ruby
        amenities: r.amenities.pluck(:name),
        add_ons: r.amenity_add_ons,
        amenity_features: r.amenity_feature_names,
```

- [ ] **Step 6: Verify the API shape**

Run (replace IDs with a real member + room from `bin/rails console`):
```bash
bin/rails runner 'r = Room.joins(:amenities).first; pp({ add_ons: r.amenity_add_ons, amenity_features: r.amenity_feature_names })'
```
Expected: prints the structured `add_ons` (with `_cents` rates) and the `amenity_features` name list. The existing `amenities` key is unchanged.

- [ ] **Step 7: Commit**
```bash
git add app/models/room.rb spec/models/room_spec.rb app/controllers/api/v1/rooms_controller.rb
git commit -m "feat: expose amenity add-ons + feature names on the room API (additive)"
```

---

## Task 4: Admin room form — two labeled rate fields, drop the toggle

Replace the Regular/Membership radio (which showed only one rate at a time) with two always-visible labeled fields. Both rates already persist via nested attributes — this is a UI correctness change.

**Files:**
- Modify: `app/views/operator/rooms/_amenity_fields.html.erb`
- Modify: `app/views/operator/rooms/_form_fields.html.erb` (remove the `amenity-type` radio block)
- Delete: `app/javascript/manage_amenity.js` (the toggle's only job)
- Modify: wherever `manage_amenity.js` is imported (find with `grep -rn "manage_amenity" app/`)

- [ ] **Step 1: Rewrite the amenity fields partial**

Replace the entire contents of `app/views/operator/rooms/_amenity_fields.html.erb` with:
```erb
<div class="nested-fields">
  <div class="form-row mx-0 amenity-container">
    <div class="form-group name-group">
      <%= f.label :name, "Amenity" %>
      <%= f.text_field :name, class: "form-control", placeholder: "e.g. Catering" %>
    </div>
    <div class="form-group">
      <%= f.label :price, "Non-member rate" %>
      <div class="input-group">
        <div class="input-group-prepend"><span class="input-group-text">$</span></div>
        <%= f.number_field :price, class: "form-control", step: 0.01, min: "0",
              placeholder: "0.00 (free)",
              value: f.object.persisted? ? f.object.price : nil %>
      </div>
    </div>
    <div class="form-group">
      <%= f.label :membership_price, "Member rate" %>
      <div class="input-group">
        <div class="input-group-prepend"><span class="input-group-text">$</span></div>
        <%= f.number_field :membership_price, class: "form-control", step: 0.01, min: "0",
              placeholder: "0.00 (free)",
              value: f.object.persisted? ? f.object.membership_price : nil %>
      </div>
    </div>
    <div class="form-group d-flex align-items-end">
      <%= link_to_remove_association "x", f, class: "btn btn-outline-danger" %>
    </div>
  </div>
  <small class="form-text text-muted">Leave both blank for a free feature (e.g. whiteboard). A rate &gt; 0 makes it a bookable add-on.</small>
</div>
```

- [ ] **Step 2: Remove the radio toggle from the room form**

In `app/views/operator/rooms/_form_fields.html.erb`, delete the entire `<div class="form-group amenity-type-price"> ... </div>` block (the two radio inputs labeled "Regular" / "Membership"). Leave the `<h4>Amenities</h4>`, the `fields_for :amenities`, and the "+ Add More" link intact.

- [ ] **Step 3: Delete the toggle JS and its import**

```bash
git rm app/javascript/manage_amenity.js
grep -rn "manage_amenity" app/   # remove any import/require line this finds (e.g. in app/javascript/application.js or packs)
```
Remove the import line(s) the grep surfaces.

- [ ] **Step 4: Verify in the browser**

Run: `bin/rails server`, then visit `/operator/rooms/<id>/edit` for a room.
Expected: each amenity row shows **both** a "Non-member rate" and "Member rate" field at once (no Regular/Membership radio). Add an amenity "Catering" with 50 / 35, save, reload the page.
Confirm persistence:
```bash
bin/rails runner 'a = Amenity.find_by(name: "Catering"); puts a ? "price=#{a.price} membership_price=#{a.membership_price}" : "not found"'
```
Expected: `price=50.0 membership_price=35.0`.

- [ ] **Step 5: Commit**
```bash
git add app/views/operator/rooms/_amenity_fields.html.erb app/views/operator/rooms/_form_fields.html.erb app/javascript/
git commit -m "feat: amenity admin form shows member + non-member rate, drop Regular/Membership toggle"
```

---

## Already done (reference, not tasks)
- `CONTEXT.md` → **Amenity** glossary entry + Flagged-ambiguities line (terms: Member rate / Non-member rate).
- `docs/adr/0007-amenity-behavior-derived-from-rate.md` — the derive-from-rate decision.

## Follow-on plans (not in this plan)
1. **Mobile** — render `amenity_features` as chips and `add_ons` as selectable rows (both rates shown, viewer's highlighted) in `ReserveNowScreen`/`ReserveLaterScreen`; send chosen `amenity_ids` on booking; show a running total. Reconcile with the existing `features` string array on the card.
2. **Booking/charge** — accept `amenity_ids` in `Api::V1::ReservationsController#create`, validate they belong to the room, attach to the reservation, and thread `amenity_price` through `Billing::Reservations::CreateRoomReservation` / `ChargeCalculator`. Server recomputes the charge; the client never sends a price.
3. **Demo seed** — idempotent rake task building a `billing_state: "demo"` operator with synthetic rooms/amenities/members/revenue, resettable for sales pitches.
