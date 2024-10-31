require "rails_helper"

RSpec.describe Operator, type: :model do
  describe "callbacks" do
    describe "after_save" do
      describe "#update_kisi_api_key_for_locations" do
        context "on save" do
          it "calls the update_kisi_api_key_for_locations method" do
            operator = build(:operator)
            expect(operator).to receive(:update_kisi_api_key_for_locations)
            operator.save
          end
        end

        context "on update" do
          it "calls the update_kisi_api_key_for_locations method" do
            operator = create(:operator)
            expect(operator).to receive(:update_kisi_api_key_for_locations)
            operator.update(billing_state: "production")
          end
        end
      end
    end
  end

  describe "#update_kisi_api_key_for_locations" do
    it "updates the kisi_api_key for all locations" do
      operator = create(:operator, kisi_api_key: "KISI1")
      location = create(:location, operator: operator)
      operator.update_kisi_api_key_for_locations
      location.reload
      expect(location.kisi_api_key).to eq("KISI1")
    end
  end
end
