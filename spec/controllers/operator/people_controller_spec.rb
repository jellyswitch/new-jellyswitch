require "rails_helper"

RSpec.describe Operator::PeopleController, type: :controller do
  render_views

  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }
  let(:admin_user) { create(:user, operator: operator, role: "superadmin", current_location: location) }
  let(:regular_user) { create(:user, operator: operator, current_location: location) }

  let!(:member) do
    u = create(:user, operator: operator, current_location: location, name: "Alice Member")
    create(:subscription, subscribable: u, billable: u, active: true)
    u
  end

  let!(:tour_taker) do
    create(:user, operator: operator, current_location: location, name: "Carol Tour")
  end

  before do
    allow(controller).to receive(:current_location).and_return(location)
    request.host = "#{operator.subdomain}.lvh.me"
  end

  describe "GET #index" do
    context "when user is admin" do
      before { allow(controller).to receive(:current_user).and_return(admin_user) }

      it "renders successfully" do
        get :index
        expect(response).to be_successful
      end

      it "assigns @people scoped to the current operator" do
        get :index
        expect(assigns(:people)).to include(member, tour_taker)
      end

      it "defaults @stage to 'all'" do
        get :index
        expect(assigns(:stage)).to eq("all")
      end

      it "filters by stage when stage param is given" do
        get :index, params: { stage: "member" }
        expect(assigns(:people)).to include(member)
        expect(assigns(:people)).not_to include(tour_taker)
      end

      it "filters by tour_taker stage" do
        get :index, params: { stage: "tour_taker" }
        expect(assigns(:people)).to include(tour_taker)
        expect(assigns(:people)).not_to include(member)
      end

      it "ignores unknown stage values and falls back to all" do
        get :index, params: { stage: "garbage" }
        expect(assigns(:stage)).to eq("all")
      end

      it "responds to JSON" do
        get :index, params: { stage: "member" }, format: :json
        body = JSON.parse(response.body)
        expect(body["stage"]).to eq("member")
        expect(body["people"].map { |p| p["id"] }).to include(member.id)
        expect(body["people"].first).to include("id", "name", "lifecycle_stage", "last_activity_at")
      end
    end

    context "when user is not staff" do
      before { allow(controller).to receive(:current_user).and_return(regular_user) }

      it "redirects away (not authorized)" do
        get :index
        expect(response).to redirect_to(root_path)
      end
    end

    context "with owned_by_me filter" do
      let!(:owned_member) do
        create(:user, operator: operator, current_location: location, name: "Owned",
                      point_of_contact: admin_user)
      end
      let!(:other_member) do
        create(:user, operator: operator, current_location: location, name: "Other")
      end

      before { allow(controller).to receive(:current_user).and_return(admin_user) }

      it "filters to people owned by the current user when owned_by_me=1" do
        get :index, params: { owned_by_me: 1 }
        expect(assigns(:owned_by_me)).to be true
        expect(assigns(:people).map(&:id)).to include(owned_member.id)
        expect(assigns(:people).map(&:id)).not_to include(other_member.id)
      end

      it "ignores the filter when owned_by_me is unset" do
        get :index
        expect(assigns(:owned_by_me)).to be false
        expect(assigns(:people).map(&:id)).to include(owned_member.id, other_member.id)
      end

      it "surfaces point_of_contact_name in JSON" do
        get :index, params: { owned_by_me: 1 }, format: :json
        body = JSON.parse(response.body)
        expect(body["owned_by_me"]).to be true
        expect(body["people"].first["point_of_contact_name"]).to eq(admin_user.name)
      end
    end
  end

  describe "GET #index with from filter" do
    let(:operator2) { create(:operator) }
    let(:tahoe_loc) { create(:location, operator: operator2, city: "South Lake Tahoe", state: "CA") }
    let(:admin2)    { create(:user, operator: operator2, role: "superadmin", original_location: tahoe_loc, current_location: tahoe_loc) }

    let!(:local_member) { create(:user, operator: operator2, role: :unassigned, name: "Local", home_city: "South Lake Tahoe", home_state: "CA") }
    let!(:reno_member)  { create(:user, operator: operator2, role: :unassigned, name: "Reno",  home_city: "Reno",            home_state: "NV") }
    let!(:bay_member)   { create(:user, operator: operator2, role: :unassigned, name: "Bay",   home_city: "Oakland",         home_state: "CA") }
    let!(:no_geo)       { create(:user, operator: operator2, role: :unassigned, name: "NoGeo", home_city: nil,               home_state: nil) }

    before do
      request.headers["X-Operator-Subdomain"] = operator2.subdomain
      ActsAsTenant.current_tenant = operator2
      allow(controller).to receive(:current_user).and_return(admin2)
      allow(controller).to receive(:current_location).and_return(tahoe_loc)
      allow(controller).to receive(:current_tenant).and_return(operator2)
    end

    it "from=local returns only members in the operator's primary city" do
      get :index, params: { from: "local" }, format: :json
      names = JSON.parse(response.body)["people"].map { |p| p["name"] }
      expect(names).to contain_exactly("Local")
    end

    it "from=out returns members with home_city set but not in primary city" do
      get :index, params: { from: "out" }, format: :json
      names = JSON.parse(response.body)["people"].map { |p| p["name"] }
      expect(names).to contain_exactly("Reno", "Bay")
    end

    it "from=state:CA returns only California members" do
      get :index, params: { from: "state:CA" }, format: :json
      names = JSON.parse(response.body)["people"].map { |p| p["name"] }
      expect(names).to contain_exactly("Local", "Bay")
    end

    it "from omitted returns all members (including those with no home_city)" do
      get :index, format: :json
      names = JSON.parse(response.body)["people"].map { |p| p["name"] }
      expect(names).to contain_exactly("Local", "Reno", "Bay", "NoGeo")
    end

    it "from=garbage is treated as no filter (graceful)" do
      get :index, params: { from: "garbage" }, format: :json
      names = JSON.parse(response.body)["people"].map { |p| p["name"] }
      expect(names.length).to eq(4)
    end

    it "response includes available_states and primary_city" do
      get :index, format: :json
      body = JSON.parse(response.body)
      expect(body["available_states"]).to contain_exactly("CA", "NV")
      expect(body["primary_city"]).to eq("South Lake Tahoe")
    end

    it "person_json includes home_city and home_state" do
      get :index, format: :json
      bay = JSON.parse(response.body)["people"].find { |p| p["name"] == "Bay" }
      expect(bay["home_city"]).to eq("Oakland")
      expect(bay["home_state"]).to eq("CA")
    end

    describe "search query q" do
      it "filters by name (case-insensitive partial match)" do
        get :index, params: { q: "alice" }, format: :json
        names = JSON.parse(response.body)["people"].map { |p| p["name"] }
        expect(names).to contain_exactly("Alice Member")
      end

      it "filters by email substring" do
        carol = User.find_by(name: "Carol Tour")
        carol.update!(email: "carol@example.com")
        get :index, params: { q: "carol@" }, format: :json
        names = JSON.parse(response.body)["people"].map { |p| p["name"] }
        expect(names).to contain_exactly("Carol Tour")
      end

      it "echoes the q value back in the JSON response" do
        get :index, params: { q: "alice" }, format: :json
        expect(JSON.parse(response.body)["q"]).to eq("alice")
      end

      it "ignores blank/whitespace q" do
        get :index, params: { q: "   " }, format: :json
        names = JSON.parse(response.body)["people"].map { |p| p["name"] }
        expect(names).to include("Alice Member", "Carol Tour")
      end

      it "composes with stage filter" do
        get :index, params: { q: "tour", stage: "tour_taker" }, format: :json
        names = JSON.parse(response.body)["people"].map { |p| p["name"] }
        expect(names).to contain_exactly("Carol Tour")
      end

      it "matches home_zip when q is a zip-like value" do
        member.update!(home_zip: "96150")
        get :index, params: { q: "96150" }, format: :json
        names = JSON.parse(response.body)["people"].map { |p| p["name"] }
        expect(names).to contain_exactly("Alice Member")
      end

      it "matches partial zip via LIKE" do
        member.update!(home_zip: "96150")
        get :index, params: { q: "961" }, format: :json
        names = JSON.parse(response.body)["people"].map { |p| p["name"] }
        expect(names).to include("Alice Member")
      end
    end

    describe "person_json includes home_zip" do
      it "surfaces home_zip in the JSON response" do
        member.update!(home_zip: "96150")
        get :index, format: :json
        alice = JSON.parse(response.body)["people"].find { |p| p["name"] == "Alice Member" }
        expect(alice["home_zip"]).to eq("96150")
      end
    end
  end
end
