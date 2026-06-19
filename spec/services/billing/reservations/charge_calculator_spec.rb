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
end
