require "rails_helper"

# Phase 4 (ADR 0013): a reservation grants building access only within
# ±building_access_window_minutes of its slot.
RSpec.describe Reservation, "#access_window_open?" do
  let(:operator) { create(:operator, billing_state: "production", building_access_window_minutes: 60) }
  let(:location) { create(:location, operator: operator) }
  let(:room) { create(:room, operator: operator, location: location) }
  let(:user) { create(:user, operator: operator) }
  let(:start) { 2.days.from_now.change(hour: 12, min: 0) }
  let(:reservation) do
    r = Reservation.new(room: room, user: user, datetime_in: start, minutes: 60)
    r.save!(validate: false)
    r
  end

  it "is open during the slot" do
    expect(reservation.access_window_open?(start + 30.minutes)).to be(true)
  end

  it "is open within the window before start" do
    expect(reservation.access_window_open?(start - 30.minutes)).to be(true)
  end

  it "is open within the window after end" do
    expect(reservation.access_window_open?(start + 90.minutes)).to be(true) # 30 min after the 60-min slot
  end

  it "is closed before the window opens" do
    expect(reservation.access_window_open?(start - 90.minutes)).to be(false)
  end

  it "is closed after the window closes" do
    expect(reservation.access_window_open?(start + 150.minutes)).to be(false) # >60 min after end
  end

  it "honors the operator's configured window" do
    operator.update!(building_access_window_minutes: 30)
    # 45 min before start is inside the default 60 window but outside a 30 window.
    expect(reservation.access_window_open?(start - 45.minutes)).to be(false)
    # An explicit window_minutes argument overrides the operator setting.
    expect(reservation.access_window_open?(start - 45.minutes, window_minutes: 60)).to be(true)
  end
end

# Phase 7 mobile surfacing: the same window, exposed as a member-facing
# "when can I get in" instant + width.
RSpec.describe Reservation, "access-window labels" do
  let(:operator) { create(:operator, billing_state: "production", building_access_window_minutes: 60) }
  let(:location) { create(:location, operator: operator) }
  let(:room) { create(:room, operator: operator, location: location) }
  let(:user) { create(:user, operator: operator) }
  let(:start) { 2.days.from_now.change(hour: 12, min: 0) }
  let(:reservation) do
    r = Reservation.new(room: room, user: user, datetime_in: start, minutes: 60)
    r.save!(validate: false)
    r
  end

  it "reads the operator's configured window width" do
    expect(reservation.building_access_window_minutes).to eq(60)
    operator.update!(building_access_window_minutes: 30)
    expect(reservation.building_access_window_minutes).to eq(30)
  end

  it "opens access the window's minutes before the slot starts" do
    expect(reservation.access_opens_at).to be_within(1.second).of(start - 60.minutes)
    operator.update!(building_access_window_minutes: 90)
    expect(reservation.access_opens_at).to be_within(1.second).of(start - 90.minutes)
  end
end
