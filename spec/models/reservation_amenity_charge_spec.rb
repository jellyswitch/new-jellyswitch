require "rails_helper"

RSpec.describe "Reservation amenity charge math" do
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
    expect(r.authorizable_charge_in_cents(overage_cents: 1200)).to eq(1200 + 5000)
  end
end
