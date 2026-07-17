require "rails_helper"

# Locks in the equivalence that justifies has_active_reservation? using the
# `ongoing` SQL scope's exists? instead of loading every reservation into Ruby
# to scan with ongoing?. The instance method computes start_at via a timezone
# round-trip while the scope compares the raw timestamptz — this proves they
# agree, including at the Pacific (non-UTC) location the factory uses by default
# (where a timezone bug would surface).
RSpec.describe "Reservation#ongoing? vs .ongoing scope", type: :model do
  def make(datetime_in:, minutes: 60)
    create(:reservation, datetime_in: datetime_in, minutes: minutes)
  end

  it "confirms the location is non-UTC (Pacific)" do
    expect(make(datetime_in: 30.minutes.ago).room.location.time_zone)
      .to eq("Pacific Time (US & Canada)")
  end

  it "both true for a currently-ongoing reservation" do
    r = make(datetime_in: 30.minutes.ago, minutes: 60) # started 30m ago, ends in 30m
    expect(r.ongoing?).to be true
    expect(Reservation.ongoing.exists?(r.id)).to be true
  end

  it "both false for a finished reservation" do
    r = make(datetime_in: 3.hours.ago, minutes: 60) # ended ~2h ago
    expect(r.ongoing?).to be false
    expect(Reservation.ongoing.exists?(r.id)).to be false
  end

  it "both false for a future reservation" do
    r = make(datetime_in: 2.hours.from_now, minutes: 60)
    expect(r.ongoing?).to be false
    expect(Reservation.ongoing.exists?(r.id)).to be false
  end

  it "has_active_reservation? matches an any?+ongoing? scan for the user" do
    user = create(:user)
    make_for = ->(dt) { create(:reservation, user: user, datetime_in: dt, minutes: 60) }
    make_for.call(3.hours.ago)      # finished
    make_for.call(30.minutes.ago)   # ongoing
    make_for.call(2.hours.from_now) # future
    ruby_way = user.reservations.any?(&:ongoing?)
    expect(user.has_active_reservation?).to eq(ruby_way)
    expect(user.has_active_reservation?).to be true
  end
end
