require 'rails_helper'

RSpec.describe Operator::CheckinsController, type: :controller do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }
  let(:admin_user) { create(:user, operator: operator, role: "superadmin", original_location: location) }
  let(:regular_user) { create(:user, operator: operator, original_location: location) }
  let(:checkin) { create(:checkin, user: regular_user, location: location) }

  before do
    allow(controller).to receive(:current_location).and_return(location)
    request.host = "#{operator.subdomain}.lvh.me"
  end

  describe "GET #new" do
    context "when user is logged in" do
      before do
        allow(controller).to receive(:current_user).and_return(regular_user)
        get :new
      end

      it "assigns @checkin" do
        expect(assigns(:checkin)).to be_a_new(Checkin)
      end

      it "includes stripe" do
        expect(assigns(:include_stripe)).to be true
      end

      it "returns http success" do
        expect(response).to have_http_status(:success)
      end
    end

    context "when user is not logged in" do
      it "redirects to root path" do
        get :new
        expect(response).to redirect_to(root_path)
      end
    end
  end

  describe "GET #required" do
    context "when user is logged in" do
      before do
        allow(controller).to receive(:current_user).and_return(regular_user)
      end

      context "when location is present" do
        before { get :required }

        it "assigns @checkin" do
          expect(assigns(:checkin)).to be_a_new(Checkin)
        end

        it "includes stripe" do
          expect(assigns(:include_stripe)).to be true
        end
      end

      context "when location is blank" do
        before do
          allow(controller).to receive(:current_location).and_return(nil)
          get :required
        end

        it "redirects to root path" do
          expect(response).to redirect_to(root_path)
        end
      end
    end
  end

  describe "POST #create" do
    before do
      allow(controller).to receive(:current_user).and_return(regular_user)
    end

    context "with stripe token" do
      let(:stripe_token) { "tok_visa" }

      context "when update payment and create checkin succeeds" do
        before do
          allow(Checkins::UpdatePaymentAndCreateCheckin).to receive(:call).and_return(
            OpenStruct.new(success?: true)
          )
        end

        it "redirects to home path" do
          post :create, params: { stripeToken: stripe_token }
          expect(response).to redirect_to(home_path)
        end
      end

      context "when update payment and create checkin fails" do
        before do
          allow(Checkins::UpdatePaymentAndCreateCheckin).to receive(:call).and_return(
            OpenStruct.new(success?: false, message: "Payment failed")
          )
        end

        it "sets error flash message" do
          post :create, params: { stripeToken: stripe_token }
          expect(flash[:error]).to be_present
        end

        it "redirects to referrer or root" do
          post :create, params: { stripeToken: stripe_token }
          expect(response).to redirect_to(root_path)
        end
      end
    end

    context "without stripe token" do
      context "when create checkin succeeds" do
        before do
          allow(Checkins::CreateCheckin).to receive(:call).and_return(
            OpenStruct.new(success?: true)
          )
        end

        it "redirects to home path" do
          post :create
          expect(response).to redirect_to(home_path)
        end
      end

      context "when create checkin fails" do
        before do
          allow(Checkins::CreateCheckin).to receive(:call).and_return(
            OpenStruct.new(success?: false, message: "Checkin failed")
          )
        end

        it "sets error flash message" do
          post :create
          expect(flash[:error]).to be_present
        end

        it "redirects to referrer or root" do
          post :create
          expect(response).to redirect_to(root_path)
        end
      end
    end
  end

  describe "GET #index" do
    before do
      allow(controller).to receive(:current_user).and_return(admin_user)
    end

    it "assigns @checkins" do
      checkin # Create the checkin
      get :index
      expect(assigns(:checkins)).to include(checkin)
    end

    it "paginates the results" do
      get :index
      expect(assigns(:pagy)).to be_present
    end
  end

  describe "GET #show" do
    before do
      allow(controller).to receive(:current_user).and_return(admin_user)
    end

    it "assigns @checkin" do
      get :show, params: { id: checkin.id }
      expect(assigns(:checkin)).to eq(checkin)
    end
  end

  describe "DELETE #destroy" do
    before do
      allow(controller).to receive(:current_user).and_return(admin_user)
      checkin # Create the checkin
    end

    context "when checkout succeeds" do
      before do
        allow(Checkins::Checkout).to receive(:call).and_return(
          OpenStruct.new(success?: true)
        )
      end

      it "sets success flash message" do
        delete :destroy, params: { id: checkin.id }
        expect(flash[:success]).to match(/You've checked out/)
      end

      it "redirects to home path" do
        delete :destroy, params: { id: checkin.id }
        expect(response).to redirect_to(home_path)
      end
    end

    context "when checkout fails" do
      before do
        allow(Checkins::Checkout).to receive(:call).and_return(
          OpenStruct.new(success?: false, message: "Checkout failed")
        )
      end

      it "sets error flash message" do
        delete :destroy, params: { id: checkin.id }
        expect(flash[:error]).to be_present
      end

      it "redirects to referrer or root" do
        delete :destroy, params: { id: checkin.id }
        expect(response).to redirect_to(root_path)
      end
    end
  end
end