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

  describe "POST #signup" do
    let!(:operator) { create(:operator, subdomain: "signup-test") }
    let!(:location) { create(:location, operator: operator) }

    before do
      request.headers["X-Operator-Subdomain"] = "signup-test"
      allow(Geocoder).to receive(:search).and_return([
        Struct.new(:city, :state_code).new("Tahoe", "CA")
      ])
      # Stub Stripe so tests don't require Stripe Connect configuration
      stripe_result = double("stripe_result", success?: true, message: nil)
      allow(CreateStripeCustomer).to receive(:call).and_return(stripe_result)
    end

    it "accepts and persists home_latitude/home_longitude" do
      post :signup, params: {
        subdomain: "signup-test",
        name: "Geo Tester", email: "geo@untethered.com",
        password: "password123", phone: "555-1234",
        home_latitude: 38.94, home_longitude: -119.98,
      }
      expect(response).to have_http_status(:ok).or have_http_status(:created)

      user = User.find_by(email: "geo@untethered.com")
      expect(user).not_to be_nil
      expect(user.home_latitude.to_f).to  be_within(0.001).of(38.94)
      expect(user.home_longitude.to_f).to be_within(0.001).of(-119.98)
      expect(user.home_city).to  eq("Tahoe")
      expect(user.home_state).to eq("CA")
    end

    it "works without home_latitude/home_longitude (backward compat)" do
      post :signup, params: {
        subdomain: "signup-test",
        name: "No Geo", email: "nogeo@untethered.com",
        password: "password123", phone: "555-5678",
      }
      expect(response).to have_http_status(:ok).or have_http_status(:created)

      user = User.find_by(email: "nogeo@untethered.com")
      expect(user).not_to be_nil
      expect(user.home_latitude).to  be_nil
      expect(user.home_longitude).to be_nil
    end
  end

  describe "POST #lookup_operators" do
    # `:user` factory requires `original_location` to be settable from
    # `operator.locations.first`, so each operator needs at least one location.
    let!(:op_a) do
      o = create(:operator, name: "Space A", subdomain: "space-a-test")
      create(:location, operator: o)
      o
    end
    let!(:op_b) do
      o = create(:operator, name: "Space B", subdomain: "space-b-test")
      create(:location, operator: o)
      o
    end
    let!(:op_c) do
      o = create(:operator, name: "Space C", subdomain: "space-c-test")
      create(:location, operator: o)
      o
    end

    it "returns operators where the email has an active user record" do
      create(:user, operator: op_a, email: "multi@example.com", archived: false)
      create(:user, operator: op_b, email: "multi@example.com", archived: false)

      post :lookup_operators, params: { email: "multi@example.com" }
      body = JSON.parse(response.body)
      subdomains = body["operators"].map { |o| o["subdomain"] }
      expect(subdomains).to contain_exactly("space-a-test", "space-b-test")
      expect(body["multiple"]).to be true
    end

    it "includes operators where the user record is archived" do
      # Soft-deleted accounts can still log in (see #login), so lookup must
      # surface their operators — otherwise the mobile brand-sticky flow
      # silently routes cross-tenant admins to the wrong space.
      create(:user, operator: op_a, email: "mixed@example.com", archived: false)
      create(:user, operator: op_b, email: "mixed@example.com", archived: true)

      post :lookup_operators, params: { email: "mixed@example.com" }
      subdomains = JSON.parse(response.body)["operators"].map { |o| o["subdomain"] }
      expect(subdomains).to contain_exactly("space-a-test", "space-b-test")
    end

    it "returns empty when the email has no users" do
      post :lookup_operators, params: { email: "nobody@example.com" }
      body = JSON.parse(response.body)
      expect(body["operators"]).to eq([])
      expect(body["multiple"]).to be false
    end

    it "returns empty when email is blank" do
      post :lookup_operators, params: { email: "" }
      expect(JSON.parse(response.body)["operators"]).to eq([])
    end

    it "matches case-insensitively and strips whitespace" do
      create(:user, operator: op_c, email: "cap@example.com", archived: false)

      post :lookup_operators, params: { email: "  CAP@Example.com  " }
      subdomains = JSON.parse(response.body)["operators"].map { |o| o["subdomain"] }
      expect(subdomains).to contain_exactly("space-c-test")
    end
  end
end
