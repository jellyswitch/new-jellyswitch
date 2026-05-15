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
end
