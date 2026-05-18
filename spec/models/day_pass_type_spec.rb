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
end
