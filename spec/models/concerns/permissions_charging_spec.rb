require "rails_helper"

RSpec.describe "charging gate (Permissions)" do
  def non_member_in(operator)
    location = create(:location, operator: operator)
    user = create(:user, operator: operator, original_location: location)
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
    operator = create(:operator, billing_state: "demo", subdomain: "southlakecoworking")
    user, location = non_member_in(operator)
    expect(user.should_charge_for_reservation?(location)).to be(false)
  end

  it "charges a non-member for a paid room only when production" do
    paid_room = ->(op) { create(:room, operator: op, location: create(:location, operator: op), hourly_rate_in_cents: 5000, rentable: true) }
    prod = create(:operator, billing_state: "production")
    demo = create(:operator, billing_state: "demo")
    expect(create(:user, operator: prod, original_location: prod.locations.first).should_charge_for_room?(paid_room.call(prod))).to be(true)
    expect(create(:user, operator: demo, original_location: demo.locations.first).should_charge_for_room?(paid_room.call(demo))).to be(false)
  end
end
