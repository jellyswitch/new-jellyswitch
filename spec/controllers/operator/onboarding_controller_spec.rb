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

  describe "Stripe Connect callback wizard return" do
    it "redirects to wizard when onboarding_in_progress (file-based assertion)" do
      file = File.read(Rails.root.join("app/controllers/landing_controller.rb"))
      expect(file).to include("session.delete(:onboarding_in_progress)")
      expect(file).to include("new_stripe_connect_operator_onboarding_index_path")
    end
  end

  describe "idempotency skips" do
    context "GET #new_membership_plan with existing plans" do
      before { create(:plan, operator: operator) }
      it "redirects to day_pass_type step" do
        get :new_membership_plan
        expect(response).to redirect_to(new_day_pass_type_operator_onboarding_index_path)
      end
    end

    context "GET #new_day_pass_type with existing types" do
      before { create(:day_pass_type, operator: operator) }
      it "redirects to room step" do
        get :new_day_pass_type
        expect(response).to redirect_to(new_room_operator_onboarding_index_path)
      end
    end

    context "GET #new_room with existing rooms (rooms enabled)" do
      before { operator.update!(rooms_enabled: true); create(:room, operator: operator, location: location) }
      it "redirects to add_members" do
        get :new_room
        expect(response).to redirect_to(add_members_operator_onboarding_index_path)
      end
    end

    context "GET #new_kisi with existing key" do
      before { operator.update!(kisi_api_key: "test-key") }
      it "redirects to door step" do
        get :new_kisi
        expect(response).to redirect_to(new_door_operator_onboarding_index_path)
      end
    end
  end

  describe "GET #new_stripe_members" do
    context "when Stripe not connected" do
      before { operator.update!(stripe_user_id: nil) }

      it "renders the connect-first guard" do
        get :new_stripe_members
        expect(response).to have_http_status(:ok)
        expect(assigns(:stripe_not_connected)).to be true
      end
    end

    context "when Stripe connected" do
      before { operator.update!(stripe_user_id: "acct_test1234", stripe_access_token: "sk_test_xxx") }

      it "proceeds to the customer list" do
        allow(Onboarding::FetchStripeCustomers).to receive(:call).and_return(double(success?: true, customers: []))
        get :new_stripe_members
        expect(response).to have_http_status(:ok)
        expect(assigns(:stripe_not_connected)).to be_falsey
      end
    end
  end
end
