require "rails_helper"

RSpec.describe Api::V1::AuthController, type: :controller do
  describe "GET #operators" do
    before { allow(Geocoder).to receive(:search).and_return([]) }

    let!(:operator) do
      o = create(:operator, name: "Cowork Tahoe Test", subdomain: "cwt-test")
      create(:location, operator: o, name: "Main",  latitude: 38.94, longitude: -119.98,
                        building_address: "1 Main St", city: "Tahoe", state: "CA")
      create(:location, operator: o, name: "Reno",  latitude: 39.53, longitude: -119.81,
                        building_address: "2 Reno St", city: "Reno", state: "NV")
      o
    end

    it "returns the operator with backward-compat keys and new primary_* + locations[]" do
      get :operators
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      op = body["operators"].find { |o| o["subdomain"] == "cwt-test" }
      expect(op).not_to be_nil

      # Backward-compat keys (mobile still consumes these)
      expect(op["location_name"]).to eq("Main")
      expect(op["city"]).to eq("Tahoe")
      expect(op["state"]).to eq("CA")

      # New keys
      expect(op["primary_latitude"].to_f).to be_within(0.001).of(38.94)
      expect(op["primary_longitude"].to_f).to be_within(0.001).of(-119.98)
      expect(op["primary_location_name"]).to eq("Main")
      expect(op["primary_city"]).to eq("Tahoe")
      expect(op["primary_state"]).to eq("CA")

      # New locations[] array
      expect(op["locations"].length).to eq(2)
      main = op["locations"].find { |l| l["name"] == "Main" }
      expect(main["latitude"].to_f).to be_within(0.001).of(38.94)
      expect(main["longitude"].to_f).to be_within(0.001).of(-119.98)
    end
  end
end
