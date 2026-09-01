require "rails_helper"

# Phase 5 (ADR 0015) end-to-end: a bundle holder opting in covers a $0 booking
# with one prepaid pass instead of being auto-charged a fresh day pass.
RSpec.describe "API v1 reserve-time bundle redemption", type: :request do
  let(:operator) { create(:operator, billing_state: "production") }
  let(:location) { create(:location, operator: operator, credits_enabled: false) }
  let(:call_room) { create(:room, operator: operator, location: location, hourly_rate_in_cents: 0, rentable: true) }
  let(:bundle_type) { create(:day_pass_type, operator: operator, location: location, quantity: 5, amount_in_cents: 10_000) }
  let(:user) { create(:user, operator: operator, original_location: location) }
  let!(:bundle) do
    DayPassBundle.create!(user: user, billable: user, operator: operator, location: location,
                          day_pass_type: bundle_type, quantity_purchased: 5, passes_remaining: 5,
                          purchased_at: Time.current)
  end

  def auth_headers_for(u)
    payload = { user_id: u.id, operator_id: u.operator_id, exp: 1.hour.from_now.to_i }
    token = JWT.encode(payload, Rails.application.secret_key_base, "HS256")
    { "Authorization" => "Bearer #{token}", "X-Operator-Subdomain" => u.operator.subdomain }
  end

  def book(use_bundle_pass:)
    # Pinned to a guaranteed OPEN weekday — member creates enforce posted
    # hours (EnforcePostedHours), and "2.days.from_now" lands on a closed
    # weekend when the suite runs late in the week.
    booking_day = Date.current.next_occurring(:tuesday) + 7
    post "/api/v1/reservations",
         params: { reservation: { room_id: call_room.id, minutes: 60, use_bundle_pass: use_bundle_pass,
                                  datetime_in: booking_day.in_time_zone.change(hour: 10, min: 0).iso8601 } },
         headers: auth_headers_for(user)
  end

  it "redeems one bundle pass and books free (no auto-purchased day pass)" do
    expect(Billing::DayPasses::CreateDayPass).not_to receive(:call) # auto-purchase must not fire

    book(use_bundle_pass: true)

    expect(response).to have_http_status(:created)
    expect(bundle.reload.passes_remaining).to eq(4)
    reservation = Reservation.find(JSON.parse(response.body)["id"])
    expect(reservation.paid).to be_falsey
    # Exactly the minted bundle pass — and it's revenue-excluded (ADR 0009).
    expect(user.day_passes.count).to eq(1)
    expect(DayPass.bundle_sourced).to include(user.day_passes.first)
    redemption = DayPassBundleRedemption.find_by(reservation_id: reservation.id, kind: "reservation")
    expect(redemption).to be_present
  end

  # ADR 0029 (Pratik/Cowork Tahoe 2026-08-26): a client that sends NO coverage
  # flags at all — the web calendar sheet, or a mobile build predating the
  # coverage-confirm prompt — books anyway; the server burns the bundle pass
  # itself instead of 422ing "This room needs a day pass".
  it "auto-redeems for a flag-less booking of an included room (no 422 dead-end)" do
    booking_day = Date.current.next_occurring(:tuesday) + 7
    post "/api/v1/reservations",
         params: { reservation: { room_id: call_room.id, minutes: 60,
                                  datetime_in: booking_day.in_time_zone.change(hour: 10, min: 0).iso8601 } },
         headers: auth_headers_for(user)

    expect(response).to have_http_status(:created)
    expect(bundle.reload.passes_remaining).to eq(4)
    reservation = Reservation.find(JSON.parse(response.body)["id"])
    expect(user.day_passes.for_day(booking_day).count).to eq(1)
    expect(DayPassBundleRedemption.find_by(reservation_id: reservation.id, kind: "reservation")).to be_present
  end

  it "does not touch the bundle when the booker doesn't opt in" do
    # Member (so the booking succeeds via membership, not the bundle) who also
    # holds a bundle — without opting in, the bundle must stay untouched.
    plan = create(:plan, operator: operator, location: location, amount_in_cents: 30_000)
    create(:subscription, subscribable: user, plan: plan, active: true, paused: false)

    book(use_bundle_pass: false)

    expect(response).to have_http_status(:created)
    expect(bundle.reload.passes_remaining).to eq(5)
  end

  # Phase 7: the mobile app surfaces the "use 1 pass" opt-in off a server-computed
  # eligibility flag on /pricing — never inferred client-side.
  describe "GET /rooms/:id/pricing (bundle_pass_redeemable flag)" do
    def pricing(room_id: call_room.id)
      get "/api/v1/rooms/#{room_id}/pricing",
          params: { date: 2.days.from_now.to_date.to_s, minutes: 60 },
          headers: auth_headers_for(user)
      JSON.parse(response.body)
    end

    it "is redeemable and reports passes remaining for an uncovered bundle holder" do
      body = pricing
      expect(body["bundle_pass_redeemable"]).to be(true)
      expect(body["bundle_passes_remaining"]).to eq(5)
    end

    it "is NOT redeemable once the booker is already covered (active subscription)" do
      plan = create(:plan, operator: operator, location: location, amount_in_cents: 30_000)
      create(:subscription, subscribable: user, plan: plan, active: true, paused: false)
      body = pricing
      expect(body["bundle_pass_redeemable"]).to be(false)
      expect(body["bundle_passes_remaining"]).to eq(5) # still owns passes, just doesn't need one
    end

    it "is NOT redeemable for a priced room (a pass doesn't cover it)" do
      priced = create(:room, operator: operator, location: location, hourly_rate_in_cents: 5_000, rentable: true)
      expect(pricing(room_id: priced.id)["bundle_pass_redeemable"]).to be(false)
    end

    it "is NOT redeemable with no passes left" do
      bundle.update!(passes_remaining: 0)
      body = pricing
      expect(body["bundle_pass_redeemable"]).to be(false)
      expect(body["bundle_passes_remaining"]).to eq(0)
    end
  end
end
