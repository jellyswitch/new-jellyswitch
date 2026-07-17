require "rails_helper"

# The three-way membership building-access tier (none / business_hours /
# all_hours) and the shared gate used by BOTH the Keys tab (has_building_access?)
# and the door-unlock authorization (Api::V1::DoorUnlocking).
RSpec.describe "Plan building_access_level" do
  include ActiveSupport::Testing::TimeHelpers

  let(:location) do
    create(:location, time_zone: "Pacific Time (US & Canada)",
                      working_day_start: "09:00", working_day_end: "18:00",
                      open_monday: true, open_sunday: false)
  end
  let(:operator) { location.operator }
  let(:user) { create(:user, operator: operator, current_location: location, original_location: location) }

  # Monday during business hours vs Monday 2am (off hours), both Pacific.
  let(:biz_time) { Time.parse("2026-07-13 12:00:00 -0700") } # Mon noon PT
  let(:off_time) { Time.parse("2026-07-13 02:00:00 -0700") } # Mon 2am PT

  def member_on(level)
    plan = create(:plan, operator: operator, location: location,
                         building_access_level: level,
                         always_allow_building_access: (level == :all_hours))
    create(:subscription, subscribable: user, billable: user, plan: plan, active: true, paused: false)
    user.reload
  end

  # Bare harness to exercise the private unlock authorization in isolation.
  let(:unlock_gate) do
    Class.new do
      include Api::V1::DoorUnlocking
      def can?(u, l) = send(:user_can_access_building?, u, l)
    end.new
  end

  describe "Location#open_at?" do
    it "is open during posted hours on an open day" do
      expect(location.open_at?(biz_time)).to be true
    end
    it "is closed outside posted hours" do
      expect(location.open_at?(off_time)).to be false
    end
    it "is closed on a non-open day even during the hours window" do
      expect(location.open_at?(Time.parse("2026-07-12 12:00:00 -0700"))).to be false # Sunday
    end
    it "handles an overnight window (e.g. 20:00–02:00)" do
      location.update!(working_day_start: "20:00", working_day_end: "02:00")
      expect(location.open_at?(Time.parse("2026-07-13 23:00:00 -0700"))).to be true  # 11pm
      expect(location.open_at?(Time.parse("2026-07-13 01:00:00 -0700"))).to be true  # 1am
      expect(location.open_at?(Time.parse("2026-07-13 12:00:00 -0700"))).to be false # noon
    end
  end

  describe "all_hours tier" do
    it "grants building access 24-7 (Keys tab and unlock)" do
      member_on(:all_hours)
      [biz_time, off_time].each do |t|
        travel_to(t) do
          expect(user.has_building_access?(location)).to be true
          expect(unlock_gate.can?(user, location)).to be true
        end
      end
    end
  end

  describe "business_hours tier" do
    before { member_on(:business_hours) }
    it "grants access during posted hours" do
      travel_to(biz_time) do
        expect(user.has_building_access?(location)).to be true
        expect(unlock_gate.can?(user, location)).to be true
      end
    end
    it "denies access outside posted hours — Keys tab AND unlock stay in sync" do
      travel_to(off_time) do
        expect(user.has_building_access?(location)).to be false
        expect(unlock_gate.can?(user, location)).to be false
      end
    end
  end

  describe "none tier (mailbox / free / community)" do
    before { member_on(:none) }
    it "never grants building access, even during hours, despite an active sub" do
      expect(user.has_active_subscription?).to be true
      [biz_time, off_time].each do |t|
        travel_to(t) do
          expect(user.has_building_access?(location)).to be false
          expect(unlock_gate.can?(user, location)).to be false # closes the old too-loose unlock hole
        end
      end
    end
  end

  describe "day-pool limit still gates a limited plan" do
    it "denies access when the member is out of days even on an all_hours plan" do
      plan = create(:plan, operator: operator, location: location,
                           building_access_level: :all_hours, has_day_limit: true, day_limit: 1)
      sub = create(:subscription, subscribable: user, billable: user, plan: plan, active: true, paused: false)
      allow_any_instance_of(Subscription).to receive(:has_days_left?).and_return(false)
      travel_to(biz_time) { expect(user.reload.has_building_access?(location)).to be false }
    end
  end
end
