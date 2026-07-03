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
  let(:member) do
    u = create(:user, operator: operator)
    member_plan = create(:plan, operator: operator, location: location, amount_in_cents: 30000)
    create(:subscription, subscribable: u, plan: member_plan, active: true, paused: false)
    u
  end
  def catering(room) = create(:amenity, room: room, name: "Catering", price: 50, membership_price: 35)

  # Regression: editing/extending a reservation re-prices through this
  # calculator (AuthorizeHold, is_extend). It must honor the same
  # member/leaseholder/staff exemption the create path applies, or a member
  # who edits a booking onto a priced room gets a hold placed + paid=true and
  # is wrongly charged (Casey Zilinek, 2026-06).
  it "exempt member on a paid room → 0 (re-price honors the room exemption)" do
    r = reservation_for(user: member, room: paid_room, minutes: 60)
    expect(member.should_charge_for_room?(paid_room, r.datetime_in.to_date)).to be(false)
    expect(described_class.call(reservation: r, minutes: 60)).to eq(0)
  end

  it "paid room + catering → hourly + non-member amenity rate" do
    r = reservation_for(user: non_member, room: paid_room, minutes: 60, amenities: [catering(paid_room)])
    expect(described_class.call(reservation: r, minutes: 60)).to eq(10000)
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

  # ── Phase 1: universal pricing (ADR 0012) ──────────────────────────────
  # rate > 0 → room rate; rate == 0 → LOCATION overage minus day-pass
  # allowance, charging even with NO coverage. Single authority.

  describe "$0 (call) room overage priced from the LOCATION rate" do
    # $12/hr = 20¢/min overage, set on the location (no longer the day pass type).
    let(:overage_location) { create(:location, operator: operator, overage_rate_in_cents: 1200) }
    let(:call_room) { create(:room, operator: operator, location: overage_location, hourly_rate_in_cents: 0) }

    def metered_day_pass(user, included_minutes)
      dpt = create(:day_pass_type, operator: operator, location: overage_location,
                                   included_meeting_room_minutes: included_minutes,
                                   # Deliberately mismatched: the charge must read the
                                   # LOCATION rate, not this stale day-pass-type rate.
                                   overage_rate_in_cents: 9999)
      create(:day_pass, user: user, billable: user, operator: operator,
                        location: overage_location, day_pass_type: dpt, day: Date.current)
    end

    it "day pass, within allowance → 0" do
      metered_day_pass(non_member, 120)
      r = reservation_for(user: non_member, room: call_room, minutes: 60)
      expect(described_class.call(reservation: r, minutes: 60)).to eq(0)
    end

    it "day pass, over allowance → LOCATION overage × over-minutes" do
      metered_day_pass(non_member, 60)
      r = reservation_for(user: non_member, room: call_room, minutes: 90)
      # 30 over-minutes × 20¢ = 600 (NOT the 9999¢/hr day-pass-type rate).
      expect(described_class.call(reservation: r, minutes: 90)).to eq(600)
    end

    it "NO day pass / no coverage → LOCATION overage × minutes (new charge)" do
      r = reservation_for(user: non_member, room: call_room, minutes: 60)
      # Previously fell through to free; now 60 × 20¢ = 1200.
      expect(described_class.call(reservation: r, minutes: 60)).to eq(1200)
    end

    it "exempt member booking a $0 room with no coverage → 0" do
      local_member = create(:user, operator: operator)
      plan = create(:plan, operator: operator, location: overage_location, amount_in_cents: 30000)
      create(:subscription, subscribable: local_member, plan: plan, active: true, paused: false)
      r = reservation_for(user: local_member, room: call_room, minutes: 60)
      expect(described_class.call(reservation: r, minutes: 60)).to eq(0)
    end

    it "demo operator → 0 even on a $0 room with no coverage" do
      demo_operator = create(:operator, billing_state: "demo")
      demo_location = create(:location, operator: demo_operator, overage_rate_in_cents: 1200)
      demo_room = create(:room, operator: demo_operator, location: demo_location, hourly_rate_in_cents: 0)
      demo_user = create(:user, operator: demo_operator)
      r = reservation_for(user: demo_user, room: demo_room, minutes: 60)
      expect(described_class.call(reservation: r, minutes: 60)).to eq(0)
    end
  end

  describe "subscription overage path is UNCHANGED (member billing untouched)" do
    let(:sub_location) { create(:location, operator: operator, overage_rate_in_cents: 1200) }
    let(:sub_call_room) { create(:room, operator: operator, location: sub_location, hourly_rate_in_cents: 0) }
    let(:metered_member) do
      u = create(:user, operator: operator)
      plan = create(:plan, operator: operator, location: sub_location, amount_in_cents: 30000,
                           included_meeting_room_minutes: 60, overage_rate_in_cents: 3000)
      create(:subscription, subscribable: u, plan: plan, active: true, paused: false)
      u
    end

    it "uses the PLAN overage rate, not the location rate" do
      r = reservation_for(user: metered_member, room: sub_call_room, minutes: 90)
      # 30 over-minutes × (3000¢/hr = 50¢/min) = 1500 — the plan rate, not 600.
      expect(described_class.call(reservation: r, minutes: 90)).to eq(1500)
    end
  end

  # Regression (Brad Flint): a booker with NO comp day pass, on a priced room,
  # always re-prices at the room's hourly rate — never the day-pass overage
  # branch — when an edit/extend re-runs this calculator.
  it "paid room re-prices at the room rate, never the overage branch (Brad)" do
    r = reservation_for(user: non_member, room: paid_room, minutes: 60)
    expect(non_member.has_active_day_pass?(r.datetime_in.to_date)).to be(false)
    expect(described_class.call(reservation: r, minutes: 120)).to eq(10000) # 2h × $50
  end
end
