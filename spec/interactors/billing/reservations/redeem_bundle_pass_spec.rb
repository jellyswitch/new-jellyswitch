require "rails_helper"

# Phase 5 (ADR 0015): opt-in reserve-time bundle redemption.
RSpec.describe Billing::Reservations::RedeemBundlePass do
  let(:operator) { create(:operator, billing_state: "production") }
  let(:location) { create(:location, operator: operator) }
  let(:call_room) { create(:room, operator: operator, location: location, hourly_rate_in_cents: 0) }
  let(:paid_room) { create(:room, operator: operator, location: location, hourly_rate_in_cents: 5000) }
  let(:bundle_type) { create(:day_pass_type, operator: operator, location: location) }
  let(:user) { create(:user, operator: operator) }

  before { ActsAsTenant.current_tenant = operator }
  after { ActsAsTenant.current_tenant = nil }

  def make_bundle(passes: 5)
    DayPassBundle.create!(user: user, billable: user, operator: operator, location: location,
                          day_pass_type: bundle_type, quantity_purchased: 5,
                          passes_remaining: passes, purchased_at: Time.current)
  end

  def reservation_for(room: call_room, at: 2.days.from_now.change(hour: 12), u: user)
    r = Reservation.new(room: room, user: u, datetime_in: at, minutes: 60)
    r.save!(validate: false)
    r
  end

  def redeem(reservation, use_bundle_pass: true, u: user)
    described_class.call(reservation: reservation, user: u, use_bundle_pass: use_bundle_pass)
  end

  it "mints a DayPass, burns one pass, and links the redemption to the reservation" do
    bundle = make_bundle(passes: 5)
    r = reservation_for

    result = redeem(r)

    expect(result).to be_a_success
    expect(bundle.reload.passes_remaining).to eq(4)
    day_pass = user.day_passes.for_location(location).for_day(r.datetime_in.to_date).first
    expect(day_pass).to be_present
    expect(day_pass.complimentary).to be_falsey # prepaid, counts toward purchased (door access)
    redemption = DayPassBundleRedemption.find_by(reservation_id: r.id, kind: "reservation")
    expect(redemption).to be_present
    expect(redemption.day_pass_id).to eq(day_pass.id)
    # The minted pass makes the booking free.
    expect(Billing::Reservations::ChargeCalculator.call(reservation: r, minutes: 60)).to eq(0)
    # And it's excluded from day-pass revenue (ADR 0009) — bundle money is
    # recognized once at sale, so the reservation-minted pass must be bundle_sourced.
    expect(DayPass.bundle_sourced).to include(day_pass)
    expect(DayPass.not_bundle_sourced).not_to include(day_pass)
  end

  it "does nothing when not opted in" do
    bundle = make_bundle
    r = reservation_for
    redeem(r, use_bundle_pass: false)
    expect(bundle.reload.passes_remaining).to eq(5)
    expect(user.day_passes.count).to eq(0)
  end

  it "does nothing for a paid room (passes never cover priced rooms)" do
    bundle = make_bundle
    r = reservation_for(room: paid_room)
    redeem(r)
    expect(bundle.reload.passes_remaining).to eq(5)
    expect(user.day_passes.count).to eq(0)
  end

  it "does nothing when the user already has a day pass for that date (no double burn)" do
    bundle = make_bundle
    r = reservation_for
    create(:day_pass, user: user, billable: user, operator: operator, location: location,
                      day_pass_type: bundle_type, day: r.datetime_in.to_date)
    redeem(r)
    expect(bundle.reload.passes_remaining).to eq(5) # untouched
  end

  it "does nothing when there is no active bundle" do
    r = reservation_for
    redeem(r)
    expect(user.day_passes.count).to eq(0)
  end

  describe "reconciliation with burn-on-entry (one pass per business-day period)" do
    let(:today_reservation) { reservation_for(at: Time.current.change(hour: 14)) }

    it "a reserve-time redemption stops the door from burning a second pass" do
      bundle = make_bundle(passes: 5)
      redeem(today_reservation)
      expect(bundle.reload.passes_remaining).to eq(4)

      Billing::DayPassBundles::ConsumeOnEntry.call(user: user, location: location)

      expect(bundle.reload.passes_remaining).to eq(4) # still 4 — no double burn
    end

    it "a door entry stops a same-day reserve-time redemption from burning again" do
      bundle = make_bundle(passes: 5)
      Billing::DayPassBundles::ConsumeOnEntry.call(user: user, location: location)
      expect(bundle.reload.passes_remaining).to eq(4)

      redeem(today_reservation)

      expect(bundle.reload.passes_remaining).to eq(4) # still 4 — already covered
    end

    it "two reservations on the same business day burn only one pass" do
      bundle = make_bundle(passes: 5)
      redeem(reservation_for(at: Time.current.change(hour: 10)))
      redeem(reservation_for(at: Time.current.change(hour: 15)))
      expect(bundle.reload.passes_remaining).to eq(4)
    end
  end

  it "rollback restores the pass and destroys the minted day pass" do
    bundle = make_bundle(passes: 5)
    r = reservation_for
    ctx = redeem(r)
    expect(bundle.reload.passes_remaining).to eq(4)

    described_class.new(ctx).rollback

    expect(bundle.reload.passes_remaining).to eq(5)
    expect(user.day_passes.count).to eq(0)
    expect(DayPassBundleRedemption.where(reservation_id: r.id, kind: "reservation").count).to eq(0)
  end
end
