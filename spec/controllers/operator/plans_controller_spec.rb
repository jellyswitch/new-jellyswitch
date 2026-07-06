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
end
