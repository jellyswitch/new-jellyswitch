# Meeting-Room Amenity Charge Integration — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax. This touches BILLING — follow superpowers:test-driven-development strictly and run the full spec for each task. Every task gets BOTH spec-compliance and code-quality review.

**Goal:** Make meeting-room amenity add-ons actually bill on the API booking path — and fix the pre-existing gap where add-ons are authorized but never captured (web path too).

**Architecture / charge invariant:** The amount AUTHORIZED (hold) and the amount CAPTURED (settlement) must BOTH equal `base + amenity_price`, where `base` is the existing room-hourly / overage / 0 charge and `amenity_price` is `Reservation#amenity_price` (member vs non-member aware). If only one side includes the amenity, `capture = min(actual, authorized)` silently drops it — so amenity cost is injected in exactly two amount-computations that must agree:
- **Hold:** `AuthorizeHold#expected_max_charge` (non-extend) → routed through a new pure method `Reservation#authorizable_charge_in_cents`.
- **Capture:** `Billing::Reservations::ChargeCalculator` (also used by the extend hold).

The money MATH lives in pure, Stripe-free methods (`amenity_price`, `charge_amount`, `authorizable_charge_in_cents`, `ChargeCalculator`) so it's exhaustively unit-testable. The Stripe hold/capture plumbing merely consumes those numbers.

**Tech Stack:** Rails, RSpec + FactoryBot. Run: `PATH="$HOME/.rbenv/shims:$PATH" bundle exec rspec <path>` (rbenv Ruby 3.3.10).

**Out of scope (separate plan):** mobile UI (display/selection); end-to-end Stripe capture verification (do manually in staging before relying on it).

---

## Charge matrix this plan must satisfy (the spec)

`should_charge_for_*` is gated on `billing_state == "production"` (foundation). `amenity_price` = non-member `price` when `should_charge_for_reservation?` is true, else member `membership_price`. Cases (production operator):

| Scenario | room_price | amenity_price | hold = capture |
|---|---|---|---|
| Non-member, paid room ($50/hr, 60m), no add-on | 5000 | 0 | 5000 |
| Non-member, paid room + catering(5000/3500) | 5000 | 5000 | 10000 |
| Member, paid room + catering | 0 (member exempt) | 3500 | 3500 |
| Non-member, free room + catering | 0 | 5000 | 5000 |
| Member, free room + catering | 0 | 3500 | 3500 |
| Free room + free amenity (0/0) | 0 | 0 | 0 (no hold) |
| Sub overage (1200) + catering, non-member | 0 | 5000 | overage 1200 + 5000 |

---

## Task 1: Amenity cost in the charge math (capture path + pure methods)

**Files:**
- Modify: `app/models/reservation.rb` (add `authorizable_charge_in_cents`; `amenity_price`/`charge_amount` already exist)
- Modify: `app/services/billing/reservations/charge_calculator.rb`
- Test: `spec/models/reservation_amenity_charge_spec.rb` (create), `spec/services/billing/reservations/charge_calculator_spec.rb` (create)

- [ ] **Step 1: Write failing specs**

Create `spec/models/reservation_amenity_charge_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe "Reservation amenity charge math" do
  # Helper: build a persisted reservation for `user` in `room` with the given
  # amenities attached, paid flag forced to match should_charge_for_room?.
  def reservation_for(user:, room:, minutes: 60, amenities: [])
    r = Reservation.new(room: room, user: user, datetime_in: Time.current.change(hour: 12), minutes: minutes)
    r.paid = user.should_charge_for_room?(room, r.datetime_in.to_date)
    r.amenities = amenities
    r.save!(validate: false)
    r
  end

  let(:operator) { create(:operator, billing_state: "production") }
  let(:location) { create(:location, operator: operator) }
  let(:paid_room) { create(:room, operator: operator, location: location, hourly_rate_in_cents: 5000, rentable: true) }
  let(:free_room) { create(:room, operator: operator, location: location, hourly_rate_in_cents: 0) }
  let(:non_member) { create(:user, operator: operator) }

  def catering(room) = create(:amenity, room: room, name: "Catering", price: 50, membership_price: 35)

  it "non-member, paid room, no add-on → room only" do
    r = reservation_for(user: non_member, room: paid_room, minutes: 60)
    expect(r.amenity_price).to eq(0)
    expect(r.charge_amount).to eq(5000)
    expect(r.authorizable_charge_in_cents).to eq(5000)
  end

  it "non-member, paid room + catering → room + non-member rate" do
    r = reservation_for(user: non_member, room: paid_room, minutes: 60, amenities: [catering(paid_room)])
    expect(r.amenity_price).to eq(5000)
    expect(r.charge_amount).to eq(10000)
    expect(r.authorizable_charge_in_cents).to eq(10000)
  end

  it "non-member, free room + catering → non-member amenity rate only" do
    r = reservation_for(user: non_member, room: free_room, minutes: 60, amenities: [catering(free_room)])
    expect(r.charge_amount).to eq(5000)
    expect(r.authorizable_charge_in_cents).to eq(5000)
  end

  it "free amenity (0/0) costs nothing" do
    free_amenity = create(:amenity, room: free_room, name: "Whiteboard", price: 0, membership_price: 0)
    r = reservation_for(user: non_member, room: free_room, minutes: 60, amenities: [free_amenity])
    expect(r.charge_amount).to eq(0)
    expect(r.authorizable_charge_in_cents).to eq(0)
  end

  it "authorizable_charge adds overage to the amenity (free room + overage + catering)" do
    r = reservation_for(user: non_member, room: free_room, minutes: 60, amenities: [catering(free_room)])
    # overage is supplied by the caller (charge_info); amenity rides on top.
    expect(r.authorizable_charge_in_cents(overage_cents: 1200)).to eq(1200 + 5000)
  end
end
```

Create `spec/services/billing/reservations/charge_calculator_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe Billing::Reservations::ChargeCalculator do
  def reservation_for(user:, room:, minutes: 60, amenities: [])
    r = Reservation.new(room: room, user: user, datetime_in: Time.current.change(hour: 12), minutes: minutes)
    r.paid = user.should_charge_for_room?(room, r.datetime_in.to_date)
    r.amenities = amenities
    r.save!(validate: false)
    r
  end

  let(:operator) { create(:operator, billing_state: "production") }
  let(:location) { create(:location, operator: operator) }
  let(:paid_room) { create(:room, operator: operator, location: location, hourly_rate_in_cents: 5000, rentable: true) }
  let(:free_room) { create(:room, operator: operator, location: location, hourly_rate_in_cents: 0) }
  let(:non_member) { create(:user, operator: operator) }
  def catering(room) = create(:amenity, room: room, name: "Catering", price: 50, membership_price: 35)

  it "paid room + catering → hourly + non-member amenity rate" do
    r = reservation_for(user: non_member, room: paid_room, minutes: 60, amenities: [catering(paid_room)])
    expect(described_class.call(reservation: r, minutes: 60)).to eq(5000 + 5000)
  end

  it "free room + catering (no overage) → amenity only" do
    r = reservation_for(user: non_member, room: free_room, minutes: 60, amenities: [catering(free_room)])
    expect(described_class.call(reservation: r, minutes: 60)).to eq(5000)
  end

  it "paid room, no add-on → unchanged (regression)" do
    r = reservation_for(user: non_member, room: paid_room, minutes: 60)
    expect(described_class.call(reservation: r, minutes: 60)).to eq(5000)
  end

  it "zero minutes → 0" do
    r = reservation_for(user: non_member, room: paid_room, minutes: 60, amenities: [catering(paid_room)])
    expect(described_class.call(reservation: r, minutes: 0)).to eq(0)
  end
end
```

- [ ] **Step 2: Run, confirm failure**

`PATH="$HOME/.rbenv/shims:$PATH" bundle exec rspec spec/models/reservation_amenity_charge_spec.rb spec/services/billing/reservations/charge_calculator_spec.rb`
Expected: failures on `authorizable_charge_in_cents` (undefined) and ChargeCalculator amenity cases (returns room-only). If a factory needs required attributes, inspect spec/factories and adjust the helper minimally; keep assertions intact; report it.

- [ ] **Step 3: Implement `authorizable_charge_in_cents` on Reservation**

In `app/models/reservation.rb`, add right after `charge_amount`:
```ruby
  # The MAX amount to authorize (hold) at booking, in cents: the room/overage
  # base plus amenity add-ons. For a paid room, overage_cents is nil and
  # charge_amount already carries room+amenity. For a free room with a plan/
  # day-pass overage, room_price is 0 so charge_amount carries only the
  # amenity, and the overage rides on top. (Overage and a paid room are
  # mutually exclusive — see SaveRoomReservation.) CaptureHold settles the
  # actual amount via ChargeCalculator, capped at this hold.
  def authorizable_charge_in_cents(overage_cents: nil)
    overage_cents.to_i + charge_amount
  end
```

- [ ] **Step 4: Implement amenity in ChargeCalculator**

In `app/services/billing/reservations/charge_calculator.rb`, replace the `call` method body so every non-zero-minute branch adds the amenity cost:
```ruby
  def call
    return 0 if minutes <= 0
    base_room_or_overage + amenity_cents
  end
```
And add these private helpers (below the existing `private` section, alongside the others):
```ruby
  # The room/overage portion — unchanged from the original logic.
  def base_room_or_overage
    if room.hourly_rate_in_cents.to_i > 0
      return ((room.hourly_rate_in_cents * minutes) / 60.0).round
    end

    day_pass = user.day_passes.where(day: date).first
    if day_pass && day_pass.day_pass_type&.has_meeting_room_limit?
      return day_pass_overage_cents(day_pass)
    end

    sub = user.active_subscription_for_location(location)
    if sub && sub.plan&.has_meeting_room_limit?
      return subscription_overage_cents(sub)
    end

    0
  end

  # Flat add-on cost for the booking (member vs non-member aware), independent
  # of minutes. Mirrors Reservation#amenity_price so hold and capture agree.
  def amenity_cents
    reservation.amenity_price
  end
```
(Delete the old room/overage logic from `call` — it now lives in `base_room_or_overage`. Keep `day_pass_overage_cents` and `subscription_overage_cents` unchanged.)

- [ ] **Step 5: Run, confirm green**

`PATH="$HOME/.rbenv/shims:$PATH" bundle exec rspec spec/models/reservation_amenity_charge_spec.rb spec/services/billing/reservations/charge_calculator_spec.rb`
Expected: all examples pass.

- [ ] **Step 6: Commit**
```
git add app/models/reservation.rb app/services/billing/reservations/charge_calculator.rb spec/models/reservation_amenity_charge_spec.rb spec/services/billing/reservations/charge_calculator_spec.rb
git commit -m "feat: amenity add-ons billed in capture math (ChargeCalculator + authorizable_charge_in_cents)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: Wire the hold to the new method + paid flag reflects paid add-ons

**Files:**
- Modify: `app/interactors/billing/reservations/authorize_hold.rb` (`expected_max_charge`, non-extend branch)
- Modify: `app/interactors/billing/reservations/save_room_reservation.rb`
- Test: `spec/interactors/billing/reservations/save_room_reservation_spec.rb` (create)

- [ ] **Step 1: Write failing spec for the paid flag**

Create `spec/interactors/billing/reservations/save_room_reservation_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe Billing::Reservations::SaveRoomReservation do
  let(:operator) { create(:operator, billing_state: "production") }
  let(:location) { create(:location, operator: operator) }
  let(:free_room) { create(:room, operator: operator, location: location, hourly_rate_in_cents: 0) }
  let(:user) { create(:user, operator: operator, payment_method: "Card") }
  let!(:catering) { create(:amenity, room: free_room, name: "Catering", price: 50, membership_price: 35) }

  it "marks the reservation paid when a free room has a paid add-on" do
    ctx = described_class.call(
      reservation_params: { room: free_room, datetime_in: Time.current.change(hour: 12), minutes: 60, amenity_ids: [catering.id] },
      user: user,
    )
    expect(ctx).to be_success
    expect(ctx.reservation.paid).to be(true)
    expect(ctx.reservation.amenities).to include(catering)
  end

  it "leaves a free room with only free amenities unpaid" do
    free_amenity = create(:amenity, room: free_room, name: "Whiteboard", price: 0, membership_price: 0)
    ctx = described_class.call(
      reservation_params: { room: free_room, datetime_in: Time.current.change(hour: 12), minutes: 60, amenity_ids: [free_amenity.id] },
      user: user,
    )
    expect(ctx.reservation.paid).to be(false)
  end
end
```

- [ ] **Step 2: Run, confirm failure** (`paid` is false for the paid add-on case):
`PATH="$HOME/.rbenv/shims:$PATH" bundle exec rspec spec/interactors/billing/reservations/save_room_reservation_spec.rb`

- [ ] **Step 3: Implement — paid flag includes paid add-ons.** In `app/interactors/billing/reservations/save_room_reservation.rb`, after the subscription-overage block and before the `if should_charge && context.user.payment_method == "None"` check, add:
```ruby
    # A paid add-on (orderable amenity) makes even a free room chargeable.
    # Check in Ruby on the just-assigned association (no DB sum on an
    # unsaved record). amenity_price (member vs non-member) is applied later.
    should_charge ||= reservation.amenities.to_a.any?(&:orderable?)
```

- [ ] **Step 4: Wire the hold to the pure method.** In `app/interactors/billing/reservations/authorize_hold.rb`, in `expected_max_charge`, replace:
```ruby
    base = context.overage_charge_amount || reservation.charge_amount
```
with:
```ruby
    base = reservation.authorizable_charge_in_cents(overage_cents: context.overage_charge_amount)
```
(Leave the extend branch — which uses `ChargeCalculator` — and the discount logic unchanged.)

- [ ] **Step 5: Run, confirm green** (and run Task 1 specs again to confirm no regression):
`PATH="$HOME/.rbenv/shims:$PATH" bundle exec rspec spec/interactors/billing/reservations/save_room_reservation_spec.rb spec/models/reservation_amenity_charge_spec.rb`

- [ ] **Step 6: Commit**
```
git add app/interactors/billing/reservations/authorize_hold.rb app/interactors/billing/reservations/save_room_reservation.rb spec/interactors/billing/reservations/save_room_reservation_spec.rb
git commit -m "feat: hold authorizes room+amenity; paid flag reflects paid add-ons

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: API accepts, validates, and associates amenity_ids

**Files:**
- Modify: `app/controllers/api/v1/reservations_controller.rb` (`create`)
- Test: `spec/requests/api/v1/reservation_amenities_spec.rb` (create) — stubs the billing interactor so no Stripe is needed.

- [ ] **Step 1: Write failing request spec.** Create `spec/requests/api/v1/reservation_amenities_spec.rb`. First inspect an existing `spec/requests/api/v1/*` spec (if any) for the auth-header helper; if none exists, authenticate by setting the JWT the app expects. Stub `Billing::Reservations::CreateRoomReservation` to capture the params and avoid Stripe:
```ruby
require "rails_helper"

RSpec.describe "API v1 reservation amenities", type: :request do
  let(:operator) { create(:operator, billing_state: "production") }
  let(:location) { create(:location, operator: operator) }
  let(:room) { create(:room, operator: operator, location: location, hourly_rate_in_cents: 0) }
  let(:user) { create(:user, operator: operator, payment_method: "Card") }
  let!(:catering) { create(:amenity, room: room, name: "Catering", price: 50, membership_price: 35) }
  let!(:whiteboard) { create(:amenity, room: room, name: "Whiteboard", price: 0, membership_price: 0) }
  let(:other_room) { create(:room, operator: operator, location: location) }
  let!(:foreign) { create(:amenity, room: other_room, name: "Foreign", price: 99, membership_price: 99) }

  before do
    # Capture what the controller forwards to the interactor; return success.
    @captured = nil
    allow(Billing::Reservations::CreateRoomReservation).to receive(:call) do |args|
      @captured = args
      r = Reservation.create!(room: room, user: user, datetime_in: Time.current.change(hour: 12), minutes: 60)
      OpenStruct.new(success?: true, reservation: r)
    end
  end

  # Replace `auth_headers(user)` with the project's actual API auth helper.
  it "forwards only this room's orderable amenity ids" do
    post "/api/v1/reservations",
         params: { reservation: { room_id: room.id, datetime_in: Time.current.change(hour: 12).iso8601, minutes: 60,
                                  amenity_ids: [catering.id, whiteboard.id, foreign.id, 999999] } },
         headers: auth_headers(user)

    expect(response).to have_http_status(:created)
    forwarded = @captured[:reservation_params][:amenity_ids]
    expect(forwarded).to eq([catering.id])   # whiteboard(free), foreign(other room), bogus id all filtered out
  end
end
```

- [ ] **Step 2: Run, confirm failure** (controller ignores amenity_ids today):
`PATH="$HOME/.rbenv/shims:$PATH" bundle exec rspec spec/requests/api/v1/reservation_amenities_spec.rb`

- [ ] **Step 3: Implement in `app/controllers/api/v1/reservations_controller.rb#create`.** Just before the `result = Billing::Reservations::CreateRoomReservation.call(` call, add the validated amenity-id resolution, and add `amenity_ids:` into the `reservation_params:` hash:
```ruby
    # Add-on amenities: accept only ids that are orderable add-ons on THIS
    # room. Anything else (free features, other rooms, bogus ids) is dropped —
    # the server never trusts client-supplied prices or memberships.
    requested_amenity_ids = Array(params.dig(:reservation, :amenity_ids)).map(&:to_i)
    amenity_ids = room.amenities.add_ons.where(id: requested_amenity_ids).pluck(:id)
```
Then in the `reservation_params:` hash passed to `CreateRoomReservation.call`, add the line `amenity_ids: amenity_ids,` alongside `room: room,`.

- [ ] **Step 4: Run, confirm green:**
`PATH="$HOME/.rbenv/shims:$PATH" bundle exec rspec spec/requests/api/v1/reservation_amenities_spec.rb`

- [ ] **Step 5: Commit**
```
git add app/controllers/api/v1/reservations_controller.rb spec/requests/api/v1/reservation_amenities_spec.rb
git commit -m "feat: API booking accepts + validates amenity add-on ids (server-authoritative)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Final gate (before any merge)
- [ ] Run the whole affected suite green:
`PATH="$HOME/.rbenv/shims:$PATH" bundle exec rspec spec/models/reservation_amenity_charge_spec.rb spec/services/billing/reservations/charge_calculator_spec.rb spec/interactors/billing/reservations/save_room_reservation_spec.rb spec/requests/api/v1/reservation_amenities_spec.rb spec/models/amenity_spec.rb spec/models/room_spec.rb`
- [ ] Note for the human: **end-to-end Stripe hold→capture is not exercised by unit specs.** Before relying on add-on billing in production, do one real add-on booking on a staging/demo operator and confirm the captured amount on the PaymentIntent equals room + amenity.
