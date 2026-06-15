require "rails_helper"

RSpec.describe "API v1 reservation amenities", type: :request do
  let(:operator) { create(:operator, billing_state: "production") }
  let(:location) { create(:location, operator: operator) }
  let(:room) { create(:room, operator: operator, location: location, hourly_rate_in_cents: 0) }
  # superadmin: true bypasses the day-pass coverage check (needs_cov) so the
  # spec reaches CreateRoomReservation without hitting Stripe or requiring a
  # DayPassType seed.
  let(:user) { create(:user, operator: operator, card_added: true, original_location: location, superadmin: true) }
  let!(:catering) { create(:amenity, room: room, name: "Catering", price: 50, membership_price: 35) }
  let!(:whiteboard) { create(:amenity, room: room, name: "Whiteboard", price: 0, membership_price: 0) }
  let(:other_room) { create(:room, operator: operator, location: location) }
  let!(:foreign) { create(:amenity, room: other_room, name: "Foreign", price: 99, membership_price: 99) }

  def auth_headers_for(user)
    payload = { user_id: user.id, operator_id: user.operator_id, exp: 1.hour.from_now.to_i }
    token = JWT.encode(payload, Rails.application.secret_key_base, "HS256")
    {
      "Authorization" => "Bearer #{token}",
      "X-Operator-Subdomain" => user.operator.subdomain,
    }
  end

  before do
    @captured = nil
    allow(Billing::Reservations::CreateRoomReservation).to receive(:call) do |args|
      @captured = args
      r = Reservation.create!(room: room, user: user, datetime_in: Time.current.change(hour: 12), minutes: 60)
      OpenStruct.new(success?: true, reservation: r)
    end
  end

  it "forwards only this room's orderable amenity ids" do
    post "/api/v1/reservations",
         params: { reservation: { room_id: room.id, datetime_in: Time.current.change(hour: 12).iso8601, minutes: 60,
                                  amenity_ids: [catering.id, whiteboard.id, foreign.id, 999999] } },
         headers: auth_headers_for(user)

    expect(response).to have_http_status(:created)
    forwarded = @captured[:reservation_params][:amenity_ids]
    expect(forwarded).to eq([catering.id])
  end
end
