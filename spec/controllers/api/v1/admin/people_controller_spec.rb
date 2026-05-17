require "rails_helper"

RSpec.describe Api::V1::Admin::PeopleController, type: :controller do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }
  let(:admin_user) { create(:user, operator: operator, role: "admin", current_location: location) }
  let(:regular_user) { create(:user, operator: operator, role: "unassigned", current_location: location) }

  def jwt_for(user)
    payload = { user_id: user.id, operator_id: user.operator_id, exp: 1.hour.from_now.to_i }
    JWT.encode(payload, Rails.application.secret_key_base, "HS256")
  end

  before do
    request.headers["X-Operator-Subdomain"] = operator.subdomain
  end

  describe "GET #index" do
    let!(:member) do
      u = create(:user, operator: operator, current_location: location, name: "Alice")
      create(:subscription, subscribable: u, billable: u, active: true)
      u
    end

    let!(:tour_taker) do
      create(:user, operator: operator, current_location: location, name: "Carol")
    end

    context "when authenticated as admin" do
      before { request.headers["Authorization"] = "Bearer #{jwt_for(admin_user)}" }

      it "returns 200 with people list" do
        get :index
        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body["stage"]).to eq("all")
        expect(body["people"].map { |p| p["id"] }).to include(member.id, tour_taker.id)
      end

      it "filters by stage" do
        get :index, params: { stage: "member" }
        body = JSON.parse(response.body)
        expect(body["stage"]).to eq("member")
        ids = body["people"].map { |p| p["id"] }
        expect(ids).to include(member.id)
        expect(ids).not_to include(tour_taker.id)
      end

      it "returns 1 page for small datasets" do
        get :index
        body = JSON.parse(response.body)
        expect(body["page"]).to eq(1)
        expect(body["total_pages"]).to eq(1)
      end

      it "renders the expected JSON shape per person" do
        get :index
        body = JSON.parse(response.body)
        person = body["people"].find { |p| p["id"] == member.id }
        expect(person.keys).to include("id", "name", "email", "photo_url",
                                      "lifecycle_stage", "last_activity_at",
                                      "point_of_contact_name")
        expect(person["lifecycle_stage"]).to eq("member")
      end

      it "falls back to 'all' for unknown stage values" do
        get :index, params: { stage: "garbage" }
        body = JSON.parse(response.body)
        expect(body["stage"]).to eq("all")
      end

      it "filters to people owned by the current_api_user when owned_by_me=1" do
        owned = create(:user, operator: operator, current_location: location,
                              name: "Owned", point_of_contact: admin_user)
        get :index, params: { owned_by_me: 1 }
        body = JSON.parse(response.body)
        expect(body["owned_by_me"]).to be true
        ids = body["people"].map { |p| p["id"] }
        expect(ids).to include(owned.id)
        expect(ids).not_to include(member.id)
      end

      it "returns point_of_contact_name in each person row" do
        owner = create(:user, operator: operator, role: User::GENERAL_MANAGER,
                              current_location: location)
        member.update!(point_of_contact: owner)
        get :index
        body = JSON.parse(response.body)
        person = body["people"].find { |p| p["id"] == member.id }
        expect(person["point_of_contact_name"]).to eq(owner.name)
      end
    end

    context "when authenticated as a non-admin user" do
      before { request.headers["Authorization"] = "Bearer #{jwt_for(regular_user)}" }

      it "returns 403 forbidden" do
        get :index
        expect(response).to have_http_status(:forbidden)
      end
    end

    context "when unauthenticated" do
      it "returns 401 unauthorized" do
        get :index
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe "GET #index with from filter" do
    let!(:local_member) { create(:user, operator: operator, role: :unassigned, name: "Local", home_city: "South Lake Tahoe", home_state: "CA") }
    let!(:reno_member)  { create(:user, operator: operator, role: :unassigned, name: "Reno",  home_city: "Reno",            home_state: "NV") }
    let!(:bay_member)   { create(:user, operator: operator, role: :unassigned, name: "Bay",   home_city: "Oakland",         home_state: "CA") }
    let!(:no_geo)       { create(:user, operator: operator, role: :unassigned, name: "NoGeo", home_city: nil,               home_state: nil) }

    before do
      location.update!(city: "South Lake Tahoe", state: "CA")
      request.headers["Authorization"] = "Bearer #{jwt_for(admin_user)}"
    end

    it "from=local filters to local members" do
      get :index, params: { from: "local" }
      body = JSON.parse(response.body)
      expect(body["people"].map { |p| p["name"] }).to contain_exactly("Local")
    end

    it "from=out filters to out-of-town" do
      get :index, params: { from: "out" }
      body = JSON.parse(response.body)
      expect(body["people"].map { |p| p["name"] }).to contain_exactly("Reno", "Bay")
    end

    it "from=state:CA filters by state" do
      get :index, params: { from: "state:CA" }
      body = JSON.parse(response.body)
      expect(body["people"].map { |p| p["name"] }).to contain_exactly("Local", "Bay")
    end

    it "response includes available_states + primary_city + from" do
      get :index
      body = JSON.parse(response.body)
      expect(body["available_states"]).to contain_exactly("CA", "NV")
      expect(body["primary_city"]).to eq("South Lake Tahoe")
      expect(body["from"]).to eq("")
    end

    it "person entries include home_city and home_state" do
      get :index
      body = JSON.parse(response.body)
      bay = body["people"].find { |p| p["name"] == "Bay" }
      expect(bay["home_city"]).to eq("Oakland")
      expect(bay["home_state"]).to eq("CA")
    end
  end
end
