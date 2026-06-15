require "rails_helper"

RSpec.describe Billing::Reservations::SaveRoomReservation do
  let(:operator) { create(:operator, billing_state: "production") }
  let(:location) { create(:location, operator: operator) }
  let(:free_room) { create(:room, operator: operator, location: location, hourly_rate_in_cents: 0) }
  let(:user) { create(:user, operator: operator, card_added: true) }
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
