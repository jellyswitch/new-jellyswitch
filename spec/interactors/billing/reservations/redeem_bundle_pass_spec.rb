require "rails_helper"

# Phase 5 (ADR 0015): opt-in reserve-time bundle redemption.
RSpec.describe Billing::Reservations::RedeemBundlePass do
  include ActiveSupport::Testing::TimeHelpers

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

  # ADR 0029 (Pratik/Cowork Tahoe 2026-08-26): holding a bundle IS the intent —
  # member self-serve bookings (enforce_coverage) burn a pass automatically,
  # with no use_bundle_pass flag from the client.
  describe "auto-redeem for member self-serve bookings" do
    def auto_redeem(reservation)
      described_class.call(reservation: reservation, user: user, enforce_coverage: true)
    end

    it "burns a pass for an included room with no flag from the client" do
      bundle = make_bundle(passes: 2)
      r = reservation_for # 2 days from now — the future date is the point

      result = auto_redeem(r)

      expect(result).to be_a_success
      expect(bundle.reload.passes_remaining).to eq(1)
      expect(user.day_passes.for_day(r.datetime_in.to_date).count).to eq(1)
    end

    it "never auto-burns for a free room that is NOT included with a day pass" do
      bundle = make_bundle
      free_uncovered = create(:room, operator: operator, location: location,
                                     hourly_rate_in_cents: 0, include_with_day_pass: false)
      auto_redeem(reservation_for(room: free_uncovered))
      expect(bundle.reload.passes_remaining).to eq(5)
    end

    it "still defers to an existing pass covering that date" do
      bundle = make_bundle
      r = reservation_for
      create(:day_pass, user: user, billable: user, operator: operator, location: location,
                        day_pass_type: bundle_type, day: r.datetime_in.to_date)
      auto_redeem(r)
      expect(bundle.reload.passes_remaining).to eq(5)
    end
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

  describe "already-covered bookers never spend a pass (door-guard symmetry)" do
    it "no-op for a member with an active subscription" do
      bundle = make_bundle
      plan = create(:plan, operator: operator, location: location, amount_in_cents: 30_000)
      create(:subscription, subscribable: user, plan: plan, active: true, paused: false)
      redeem(reservation_for)
      expect(bundle.reload.passes_remaining).to eq(5)
      expect(DayPassBundleRedemption.where(kind: "reservation")).to be_empty
    end

    it "no-op for an active leaseholder" do
      bundle = make_bundle
      create(:office_lease, user: user, organization: nil, operator: operator, location: location)
      redeem(reservation_for)
      expect(bundle.reload.passes_remaining).to eq(5)
      expect(DayPassBundleRedemption.where(kind: "reservation")).to be_empty
    end
  end

  describe "one pass per business-day window across the 4am rollover" do
    # UTC location so the window math (anchor 04:00) is drift-free.
    let(:utc_location) { create(:location, operator: operator, time_zone: "UTC", day_pass_period_start: "04:00") }
    let(:utc_room) { create(:room, operator: operator, location: utc_location, hourly_rate_in_cents: 0) }
    let(:utc_type) { create(:day_pass_type, operator: operator, location: utc_location) }
    let!(:utc_bundle) do
      DayPassBundle.create!(user: user, billable: user, operator: operator, location: utc_location,
                            day_pass_type: utc_type, quantity_purchased: 5, passes_remaining: 5,
                            purchased_at: Time.current)
    end

    def utc_reservation(time)
      r = Reservation.new(room: utc_room, user: user, datetime_in: time, minutes: 60)
      r.save!(validate: false)
      r
    end

    it "two reservations straddling midnight in one window burn only one pass" do
      # Both fall in the window [2026-06-25 04:00, 2026-06-26 04:00) UTC.
      a = utc_reservation(Time.utc(2026, 6, 25, 23, 30))
      b = utc_reservation(Time.utc(2026, 6, 26, 0, 30))
      described_class.call(reservation: a, user: user, use_bundle_pass: true)
      described_class.call(reservation: b, user: user, use_bundle_pass: true)
      expect(utc_bundle.reload.passes_remaining).to eq(4)
    end

    it "a reservation burn stops a door entry later the same window (after midnight) from burning again" do
      a = utc_reservation(Time.utc(2026, 6, 25, 23, 0))
      described_class.call(reservation: a, user: user, use_bundle_pass: true)
      expect(utc_bundle.reload.passes_remaining).to eq(4)

      travel_to(Time.utc(2026, 6, 26, 1, 30)) do
        result = Billing::DayPassBundles::ConsumeOnEntry.call(user: user, location: utc_location)
        expect(result.outcome).to eq(:already_covered)
      end
      expect(utc_bundle.reload.passes_remaining).to eq(4) # still one pass total
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
