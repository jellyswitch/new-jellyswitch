require "rails_helper"

RSpec.describe Operator::OnboardingController, type: :controller do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }
  let(:admin)    { create(:user, operator: operator, role: "superadmin", original_location: location, current_location: location) }

  before do
    request.headers["X-Operator-Subdomain"] = operator.subdomain
    ActsAsTenant.current_tenant = operator
    allow(controller).to receive(:current_user).and_return(admin)
    allow(controller).to receive(:current_location).and_return(location)
    allow(controller).to receive(:current_tenant).and_return(operator)
  end

  describe "GET #new_stripe_connect" do
    context "when not connected" do
      before { operator.update!(stripe_user_id: nil) }

      it "renders the connect prompt and sets onboarding_in_progress session flag" do
        get :new_stripe_connect
        expect(response).to have_http_status(:ok)
        expect(session[:onboarding_in_progress]).to be true
      end
    end

    context "when already connected" do
      before { operator.update!(stripe_user_id: "acct_test1234", stripe_access_token: "sk_test_xxx") }

      it "renders the connected status" do
        get :new_stripe_connect
        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe "POST #complete_stripe_connect" do
    it "redirects to membership plan step and clears the onboarding session flag" do
      session[:onboarding_in_progress] = true
      post :complete_stripe_connect
      expect(response).to redirect_to(new_membership_plan_operator_onboarding_index_path)
      expect(session[:onboarding_in_progress]).to be_nil
    end
  end
end
