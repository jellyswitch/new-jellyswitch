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
    u = create(:user, operator: operator, current_location: location, name: "Carol Tour")
    # tour_taker stage now requires an actual `tour` Activity (User.in_stage was
    # changed so it's no longer the catch-all fallback for users with no tour).
    Activity.create!(user: u, operator: operator, kind: "tour", occurred_at: Time.current, subject: u)
    u
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

      describe "cross-location scoping (Fulton vs Zephyr Cove leak)" do
        # Reproduces the 2026-06-01 bug: GM browsing Untethered Fulton's
        # People page was shown every Untethered user across Lake Tahoe,
        # Zephyr Cove, AND Fulton. Mirrors the prior Today's Activity leak
        # fix from 2026-05-19 — both stem from scoping on operator (tenant)
        # without narrowing to current_location.
        let!(:other_location) { create(:location, operator: operator) }
        let!(:other_loc_member) do
          create(:user,
                 operator: operator,
                 current_location: other_location,
                 original_location: other_location,
                 name: "Bob OtherLocation")
        end

        it "excludes users from a different location on the same operator" do
          get :index
          names = assigns(:people).map(&:name)
          expect(names).to include("Alice Member", "Carol Tour")
          expect(names).not_to include("Bob OtherLocation")
        end
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

    context "Log Tour quick action (per-row)" do
      before { allow(controller).to receive(:current_user).and_return(admin_user) }

      it "renders a Log Tour trigger on each person row" do
        get :index
        # member + tour_taker = 2 rows = 2 triggers
        triggers = response.body.scan(/data-action="click->log-tour-modal#prepare"/)
        expect(triggers.length).to be >= 2
      end

      it "renders exactly one shared Log Tour modal element" do
        get :index
        expect(response.body.scan('id="sharedLogTourModal"').length).to eq(1)
        expect(response.body).to include('data-controller="log-tour-modal"')
      end

      it "encodes the user's name and log_tour URL as Stimulus params on the button" do
        get :index
        expect(response.body).to include("data-log-tour-modal-name-param=\"Alice Member\"")
        expect(response.body).to include("data-log-tour-modal-url-param=\"#{Rails.application.routes.url_helpers.user_log_tour_path(member)}\"")
      end
    end
  end

  describe "GET #index with from filter" do
    let(:operator2) { create(:operator) }
    let(:tahoe_loc) { create(:location, operator: operator2, city: "South Lake Tahoe", state: "CA") }
    let(:admin2)    { create(:user, operator: operator2, role: "superadmin", original_location: tahoe_loc, current_location: tahoe_loc) }

    # original_location must be set explicitly: the People page scopes by
    # original_location_id (so the GM sees only the cohort that signed up
    # *at this location*). Production users always have it; tests must too.
    let!(:local_member) { create(:user, operator: operator2, original_location: tahoe_loc, role: :unassigned, name: "Local", home_city: "South Lake Tahoe", home_state: "CA") }
    let!(:reno_member)  { create(:user, operator: operator2, original_location: tahoe_loc, role: :unassigned, name: "Reno",  home_city: "Reno",            home_state: "NV") }
    let!(:bay_member)   { create(:user, operator: operator2, original_location: tahoe_loc, role: :unassigned, name: "Bay",   home_city: "Oakland",         home_state: "CA") }
    let!(:no_geo)       { create(:user, operator: operator2, original_location: tahoe_loc, role: :unassigned, name: "NoGeo", home_city: nil,               home_state: nil) }

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
      # These exercise the top-level member/tour_taker (Alice/Carol), who live on
      # `operator`/`location`. The enclosing "from filter" context views a
      # different operator (operator2/tahoe_loc), which would scope them out — so
      # point the controller back at operator1's admin + location here.
      before do
        allow(controller).to receive(:current_tenant).and_return(operator)
        allow(controller).to receive(:current_user).and_return(admin_user)
        allow(controller).to receive(:current_location).and_return(location)
      end

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
      # Exercises the top-level member (operator/location); see the search-q
      # block above — the enclosing context views operator2, which scopes Alice
      # out, so re-point the controller at operator1.
      before do
        allow(controller).to receive(:current_tenant).and_return(operator)
        allow(controller).to receive(:current_user).and_return(admin_user)
        allow(controller).to receive(:current_location).and_return(location)
      end

      it "surfaces home_zip in the JSON response" do
        member.update!(home_zip: "96150")
        get :index, format: :json
        alice = JSON.parse(response.body)["people"].find { |p| p["name"] == "Alice Member" }
        expect(alice["home_zip"]).to eq("96150")
      end
    end
  end

  describe "GET #waitlist (office fairness queue)" do
    before do
      allow(controller).to receive(:current_location).and_return(location)
    end

    let!(:prospect) do
      u = create(:user, operator: operator, current_location: location, original_location: location, name: "Pat Prospect")
      InterestTag.record(user: u, product: "office", source: "concierge")
      u
    end

    context "as an admin" do
      before { allow(controller).to receive(:current_user).and_return(admin_user) }

      it "renders and lists office-interest people with the demand stat" do
        get :waitlist
        expect(response).to be_successful
        expect(assigns(:entries).map(&:user)).to include(prospect)
        expect(assigns(:demand)[:waiting_count]).to eq(1)
        expect(response.body).to include("Pat Prospect")
      end
    end

    context "as a non-staff user" do
      before { allow(controller).to receive(:current_user).and_return(regular_user) }

      it "is not authorized" do
        get :waitlist
        expect(response).to redirect_to(root_path)
      end
    end
  end

  describe "working the queue one-by-one" do
    let!(:prospect) do
      u = create(:user, operator: operator, current_location: location, original_location: location, name: "Pat Prospect")
      InterestTag.record(user: u, product: "office", source: "concierge")
      u
    end
    let!(:office) { create(:office, operator: operator, location: location, name: "Pipkin Suite") }

    before do
      allow(controller).to receive(:current_location).and_return(location)
      allow(controller).to receive(:current_user).and_return(admin_user)
    end

    it "POST #office_offer logs an office_offered Activity and returns to the queue" do
      expect {
        post :office_offer, params: { user_id: prospect.id, office_id: office.id }
      }.to change { prospect.activities.where(kind: "office_offered").count }.by(1)
      expect(response).to redirect_to(waitlist_people_path)
    end

    it "POST #office_decline logs an office_declined Activity" do
      expect {
        post :office_decline, params: { user_id: prospect.id }
      }.to change { prospect.activities.where(kind: "office_declined").count }.by(1)
      expect(response).to redirect_to(waitlist_people_path)
    end

    it "denies outreach to a non-staff user" do
      allow(controller).to receive(:current_user).and_return(regular_user)
      post :office_offer, params: { user_id: prospect.id }
      expect(response).to redirect_to(root_path)
      expect(prospect.activities.where(kind: "office_offered")).to be_empty
    end
  end

  describe "GET #index interest filter (ADR 0022)" do
    before { allow(controller).to receive(:current_user).and_return(admin_user) }

    let!(:office_person) do
      u = create(:user, operator: operator, current_location: location, original_location: location, name: "Olive Office")
      InterestTag.record(user: u, product: "office", source: "concierge")
      u
    end

    it "narrows the list to people holding the interest tag" do
      get :index, params: { interest: "office" }
      expect(assigns(:interest)).to eq("office")
      names = assigns(:people).map(&:name)
      expect(names).to include("Olive Office")
      expect(names).not_to include("Alice Member")
    end

    it "ignores an unknown interest product" do
      get :index, params: { interest: "parking" }
      expect(assigns(:interest)).to be_nil
      expect(assigns(:people).map(&:name)).to include("Alice Member")
    end

    it "preserves the interest filter across the other controls (search + stage tabs)" do
      get :index, params: { interest: "office" }
      # search form has a hidden interest field so refining a search keeps it
      expect(response.body).to include('name="interest"')
      # stage tabs / geo / owned-toggle links carry it too
      expect(response.body).to include("interest=office")
    end
  end

  describe "POST #message_list (seed a draft campaign)" do
    before { allow(controller).to receive(:current_user).and_return(admin_user) }

    it "creates a draft campaign seeded with the interest segment and redirects to its editor" do
      expect {
        post :message_list, params: { interest: "membership" }
      }.to change { Campaign.where(operator: operator).count }.by(1)

      campaign = Campaign.where(operator: operator).order(:created_at).last
      expect(campaign.status).to eq("draft")
      expect(campaign.segment["interest_products"]).to eq(["membership"])
      expect(campaign.segment["interest_match"]).to eq("any")
      expect(response).to redirect_to(edit_campaign_path(campaign))
    end

    it "is denied to a non-staff user" do
      allow(controller).to receive(:current_user).and_return(regular_user)
      expect {
        post :message_list, params: { interest: "membership" }
      }.not_to change { Campaign.count }
      expect(response).to redirect_to(root_path)
    end
  end
end
