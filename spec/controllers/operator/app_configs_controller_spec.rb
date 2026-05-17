require "rails_helper"

RSpec.describe Operator::AppConfigsController, type: :controller do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }
  let(:admin_user) { create(:user, operator: operator, role: "admin", original_location: location) }
  let(:superadmin_user) { create(:user, operator: operator, role: "superadmin", original_location: location) }

  before do
    allow(controller).to receive(:current_location).and_return(location)
    request.host = "#{operator.subdomain}.lvh.me"
  end

  context "as a regular admin (not superadmin)" do
    before { allow(controller).to receive(:current_user).and_return(admin_user) }

    it "redirects away from #index" do
      get :index
      expect(response.status).to be_in([302, 403])
    end
  end

  context "as a superadmin" do
    before { allow(controller).to receive(:current_user).and_return(superadmin_user) }

    it "allows access to #index" do
      get :index
      expect(response).to have_http_status(:ok)
    end
  end
end
