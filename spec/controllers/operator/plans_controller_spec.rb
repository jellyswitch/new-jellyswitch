require "rails_helper"

RSpec.describe Operator::PlansController, type: :controller do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }
  let(:admin_user) { create(:user, operator: operator, role: "superadmin", original_location: location) }

  before do
    allow(controller).to receive(:current_location).and_return(location)
    request.host = "#{operator.subdomain}.lvh.me"
    allow(controller).to receive(:current_user).and_return(admin_user)
  end

  describe "PATCH #update — Day Pool (day_limit)" do
    let(:plan) { create(:plan, operator: operator, location: location, has_day_limit: true, day_limit: 5) }

    it "persists an edited day_limit (was silently dropped from plan_update_params)" do
      patch :update, params: { id: plan.id, plan: { day_limit: 3 } }
      expect(plan.reload.day_limit).to eq(3)
    end

    it "persists toggling has_day_limit off" do
      patch :update, params: { id: plan.id, plan: { has_day_limit: false } }
      expect(plan.reload.has_day_limit).to be(false)
    end
  end

  describe "PATCH #update — Commitment Length (commitment_interval)" do
    let(:plan) { create(:plan, operator: operator, location: location) }

    it "persists an edited commitment_interval (was silently dropped from plan_update_params)" do
      patch :update, params: { id: plan.id, plan: { commitment_interval: 2 } }
      expect(plan.reload.commitment_interval).to eq(2)
    end

    it "clears commitment_interval when the field is blanked" do
      plan.update!(commitment_interval: 6)
      patch :update, params: { id: plan.id, plan: { commitment_interval: "" } }
      expect(plan.reload.commitment_interval).to be_nil
    end
  end

  # End-to-end proof that the three-way building-access SELECTOR works: the
  # forms render it, and each choice actually saves through the controller +
  # strong params (not just the model logic in building_access_level_spec).
  describe "building_access_level selector (the access-tier buttons)" do
    render_views
    # current_location is a SessionsHelper method the VIEW resolves directly, so
    # the controller-level stub above doesn't reach the rendered form. Stub the
    # helper too so the (unrelated) plan-category field can render.
    before { allow_any_instance_of(SessionsHelper).to receive(:current_location).and_return(location) }

    let(:plan) { create(:plan, operator: operator, location: location, building_access_level: :all_hours) }

    it "the EDIT form renders the three-tier select" do
      get :edit, params: { id: plan.id }
      expect(response.body).to include('name="plan[building_access_level]"')
      %w[No\ building\ access Business\ hours\ only 24/7\ access].each do |label|
        expect(response.body).to include(label)
      end
    end

    it "the NEW form renders the three-tier select" do
      get :new
      expect(response.body).to include('name="plan[building_access_level]"')
      expect(response.body).to include("Business hours only")
    end

    %w[none business_hours all_hours].each do |level|
      it "saving the edit persists building_access_level = #{level}" do
        patch :update, params: { id: plan.id, plan: { building_access_level: level } }
        expect(plan.reload.building_access_level).to eq(level)
      end
    end

    it "the SHOW page displays the chosen tier" do
      plan.update!(building_access_level: :business_hours)
      get :show, params: { id: plan.id }
      expect(response.body).to include("Business hours only")
    end
  end
end
