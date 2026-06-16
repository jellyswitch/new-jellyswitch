# == Schema Information
#
# Table name: day_pass_types
#
#  id                            :bigint(8)        not null, primary key
#  always_allow_building_access  :boolean          default(FALSE), not null
#  amount_in_cents               :integer          default(0), not null
#  available                     :boolean          default(TRUE), not null
#  code                          :string
#  default_for_room_booking      :boolean          default(FALSE), not null
#  included_meeting_room_minutes :integer
#  name                          :string           not null
#  overage_rate_in_cents         :integer          default(0), not null
#  visible                       :boolean          default(TRUE), not null
#  created_at                    :datetime         not null
#  updated_at                    :datetime         not null
#  location_id                   :integer
#  operator_id                   :integer          not null
#
# Indexes
#
#  index_day_pass_types_on_location_id  (location_id)
#  index_dpt_on_op_loc_default          (operator_id,location_id,default_for_room_booking)
#
require "rails_helper"

RSpec.describe DayPassType, type: :model do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }

  describe ".for_code" do
    let!(:cafe) { create(:day_pass_type, operator: operator, location: location, code: "CoworkCafe", name: "Cafe Hour Pass") }

    it "matches the exact stored code" do
      expect(DayPassType.for_code("CoworkCafe")).to include(cafe)
    end

    it "matches case-insensitively (Shelley's bug — coworkcafe / COWORKCAFE)" do
      expect(DayPassType.for_code("coworkcafe")).to include(cafe)
      expect(DayPassType.for_code("COWORKCAFE")).to include(cafe)
      expect(DayPassType.for_code("CoworkCAFE")).to include(cafe)
    end

    it "strips surrounding whitespace" do
      expect(DayPassType.for_code(" CoworkCafe ")).to include(cafe)
      expect(DayPassType.for_code("\tcoworkcafe\n")).to include(cafe)
    end

    it "returns nothing for a different code" do
      expect(DayPassType.for_code("OtherCode")).to be_empty
    end

    it "tolerates nil without error" do
      expect { DayPassType.for_code(nil).to_a }.not_to raise_error
    end
  end

  describe "quantity / bundles" do
    it "defaults quantity to 1 and is not a bundle" do
      t = create(:day_pass_type, operator: create(:operator))
      expect(t.quantity).to eq(1)
      expect(t.bundle?).to be(false)
    end

    it "is a bundle when quantity > 1" do
      t = create(:day_pass_type, operator: create(:operator), quantity: 5)
      expect(t.bundle?).to be(true)
    end

    it "rejects quantity < 1" do
      t = build(:day_pass_type, operator: create(:operator), quantity: 0)
      expect(t).not_to be_valid
      expect(t.errors[:quantity]).to be_present
    end
  end
end
