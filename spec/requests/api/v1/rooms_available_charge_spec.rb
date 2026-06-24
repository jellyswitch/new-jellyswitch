require "rails_helper"

# The room LIST must agree with the per-room /pricing summary: a day-passer DOES
# pay for a priced room (not "Free"), and covered rooms read "Included with …".
RSpec.describe "API v1 /rooms/available per-room charge", type: :request do
  let(:operator) { create(:operator, billing_state: "production") }
  let(:location) { create(:location, operator: operator, credits_enabled: false) }
  let!(:call_room)   { create(:room, operator: operator, location: location, hourly_rate_in_cents: 0,    rentable: true) }
  let!(:priced_room) { create(:room, operator: operator, location: location, hourly_rate_in_cents: 5000, rentable: true) }
  let(:user) { create(:user, operator: operator, original_location: location) }
  let(:date) { 2.days.from_now.to_date }

  def auth(u)
    payload = { user_id: u.id, operator_id: u.operator_id, exp: 1.hour.from_now.to_i }
    { "Authorization" => "Bearer #{JWT.encode(payload, Rails.application.secret_key_base, 'HS256')}",
      "X-Operator-Subdomain" => u.operator.subdomain }
  end

  def charges
    get "/api/v1/rooms/available", params: { date: date.to_s, time: "10:00", minutes: 60 }, headers: auth(user)
    expect(response).to have_http_status(:ok)
    JSON.parse(response.body)["available_rooms"].to_h { |r| [r["id"], r["charge"]] }
  end

  it "charges a day-passer for a priced room, labels the free room 'Included with day pass'" do
    create(:day_pass, user: user, operator: operator, location: location, day: date)
    c = charges
    expect(c[priced_room.id]).to include("cents" => 5000, "label" => nil) # 60 min × $50/hr
    expect(c[call_room.id]).to include("cents" => 0, "label" => "Included with day pass")
  end

  it "labels rooms 'Included with membership' for a member" do
    plan = create(:plan, operator: operator, location: location, amount_in_cents: 30_000)
    create(:subscription, subscribable: user, plan: plan, active: true, paused: false)
    c = charges
    expect(c[priced_room.id]["label"]).to eq("Included with membership")
    expect(c[call_room.id]["label"]).to eq("Included with membership")
  end
end
