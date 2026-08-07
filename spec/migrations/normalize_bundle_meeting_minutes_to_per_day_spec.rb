require "rails_helper"
require Rails.root.join("db/migrate/20260807210000_normalize_bundle_meeting_minutes_to_per_day.rb")

RSpec.describe NormalizeBundleMeetingMinutesToPerDay do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }

  def bundle_type(quantity:, minutes:)
    create(:day_pass_type, operator: operator, location: location,
           quantity: quantity, included_meeting_room_minutes: minutes, amount_in_cents: 7000)
  end

  it "normalizes the 180-per-pass pool pattern to the per-day allowance and leaves everything else alone" do
    ActsAsTenant.with_tenant(operator) do
      two_pack   = bundle_type(quantity: 2, minutes: 360)  # 180 × 2 pool → per-day 180
      five_pack  = bundle_type(quantity: 5, minutes: 900)  # 180 × 5 pool → per-day 180
      custom     = bundle_type(quantity: 2, minutes: 240)  # operator-set custom value → untouched
      unlimited  = bundle_type(quantity: 30, minutes: nil) # no meeting limit → untouched
      single     = bundle_type(quantity: 1, minutes: 180)  # single pass → untouched

      described_class.new.up

      expect(two_pack.reload.included_meeting_room_minutes).to eq(180)
      expect(five_pack.reload.included_meeting_room_minutes).to eq(180)
      expect(custom.reload.included_meeting_room_minutes).to eq(240)
      expect(unlimited.reload.included_meeting_room_minutes).to be_nil
      expect(single.reload.included_meeting_room_minutes).to eq(180)
    end
  end
end
