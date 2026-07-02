require "rails_helper"

# Phase 2 (ADR 0010/0011): invoices link back to their reservation so a cancel
# can refund all of them (booking capture + extension deltas).
RSpec.describe Reservation, "#invoices" do
  let(:operator) { create(:operator, billing_state: "production") }
  let(:location) { create(:location, operator: operator) }
  let(:room) { create(:room, operator: operator, location: location, hourly_rate_in_cents: 5000) }
  let(:user) { create(:user, operator: operator) }
  let(:reservation) do
    r = Reservation.new(room: room, user: user, datetime_in: Time.current.change(hour: 12), minutes: 60)
    r.save!(validate: false)
    r
  end

  it "collects all invoices stamped with the reservation" do
    booking = create(:invoice, operator: operator, location: location, billable: user, reservation: reservation)
    extension = create(:invoice, operator: operator, location: location, billable: user, reservation: reservation)
    create(:invoice, operator: operator, location: location, billable: user) # unrelated, no reservation

    expect(reservation.invoices).to contain_exactly(booking, extension)
    expect(booking.reservation).to eq(reservation)
  end

  it "nullifies invoices when the reservation is destroyed (keeps the financial record)" do
    booking = create(:invoice, operator: operator, location: location, billable: user, reservation: reservation)
    reservation.destroy!
    expect(booking.reload.reservation_id).to be_nil
  end
end
