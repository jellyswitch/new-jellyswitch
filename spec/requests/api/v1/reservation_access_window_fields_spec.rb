require "rails_helper"

# Phase 7 mobile surfacing: the reservations index and the dashboard's
# next_reservation expose WHEN door access opens for an upcoming booking, so the
# app can show "you can get in from …". Both serialize off Reservation#access_opens_at
# (covered in spec/models/reservation_access_window_spec.rb); here we assert the
# fields ride the JSON, formatted like the other reservation times.
RSpec.describe "API v1 reservation access-window fields", type: :request do
  let(:operator) { create(:operator, billing_state: "production", building_access_window_minutes: 45) }
  let(:location) { create(:location, operator: operator) }
  let(:room) { create(:room, operator: operator, location: location, hourly_rate_in_cents: 0, rentable: true) }
  let(:user) { create(:user, operator: operator, original_location: location) }
  let!(:reservation) do
    r = Reservation.new(room: room, user: user, datetime_in: 2.days.from_now.change(hour: 14, min: 0), minutes: 60)
    r.save!(validate: false)
    r
  end

  def auth_headers_for(u)
    payload = { user_id: u.id, operator_id: u.operator_id, exp: 1.hour.from_now.to_i }
    token = JWT.encode(payload, Rails.application.secret_key_base, "HS256")
    { "Authorization" => "Bearer #{token}", "X-Operator-Subdomain" => u.operator.subdomain }
  end

  # Expected label, derived the same way the (separately tested) model method does
  # — keeps the assertion timezone-agnostic rather than hardcoding a wall clock.
  let(:expected_label) { reservation.access_opens_at.strftime("%l:%M %p").strip }

  it "rides the reservations index on an upcoming booking" do
    get "/api/v1/reservations", headers: auth_headers_for(user)

    expect(response).to have_http_status(:ok)
    res = JSON.parse(response.body)["upcoming"].find { |r| r["id"] == reservation.id }
    expect(res).to be_present
    expect(res["access_window_minutes"]).to eq(45)
    expect(res["access_opens_label"]).to eq(expected_label)
  end

  it "rides the dashboard next_reservation" do
    get "/api/v1/dashboard", headers: auth_headers_for(user)

    expect(response).to have_http_status(:ok)
    nxt = JSON.parse(response.body)["next_reservation"]
    expect(nxt).to be_present
    expect(nxt["access_window_minutes"]).to eq(45)
    expect(nxt["access_opens_label"]).to eq(expected_label)
  end
end
