require 'rails_helper'

RSpec.describe Operator::DayPassesController, type: :controller do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }
  let(:admin_user) { create(:user, operator: operator, role: "superadmin", original_location: location) }
  let(:regular_user) { create(:user, operator: operator, original_location: location) }
  let(:day_pass_type) { create(:day_pass_type, operator: operator, location: location) }
  let(:day_pass) { create(:day_pass, operator: operator, location: location, user: regular_user, day_pass_type: day_pass_type) }

  before do
    allow(controller).to receive(:current_location).and_return(location)
    request.host = "#{operator.subdomain}.lvh.me"
  end

  describe "GET #index" do
    before do
      allow(controller).to receive(:current_user).and_return(admin_user)
      day_pass
      get :index
    end

    it "assigns @day_passes" do
      expect(assigns(:day_passes)).to include(day_pass)
    end
  end

  describe "GET #new" do
    before do
      allow(controller).to receive(:current_user).and_return(regular_user)
    end

    context "when day pass type is specified" do
      before { get :new, params: { day_pass_type_id: day_pass_type.id } }

      it "assigns @day_pass" do
        expect(assigns(:day_pass)).to be_a_new(DayPass)
      end

      it "assigns @day_pass_type" do
        expect(assigns(:day_pass_type)).to eq(day_pass_type)
      end

      it "includes stripe" do
        expect(assigns(:include_stripe)).to be true
      end
    end
  end

  describe "POST #create" do
    before do
      allow(controller).to receive(:current_user).and_return(regular_user)
    end

    let(:valid_params) do
      {
        day_pass: {
          day: Date.current,
          day_pass_type: day_pass_type.id
        }
      }
    end

    context "with stripe token" do
      let(:stripe_token) { "tok_visa" }

      context "when successful" do
        before do
          allow(DayPassInteractorFactory).to receive_message_chain(:for, :call).and_return(
            OpenStruct.new(success?: true, day_pass: day_pass)
          )
        end

        it "creates a day pass" do
          post :create, params: valid_params.merge(stripeToken: stripe_token)
          expect(flash[:success]).to match(/Welcome/)
        end

        it "redirects to home path" do
          post :create, params: valid_params.merge(stripeToken: stripe_token)
          expect(response).to redirect_to(home_path)
        end
      end

      context "when unsuccessful" do
        before do
          allow(DayPassInteractorFactory).to receive_message_chain(:for, :call).and_return(
            OpenStruct.new(success?: false, message: "Error", day_pass: DayPass.new)
          )
        end

        it "sets error flash message" do
          post :create, params: valid_params.merge(stripeToken: stripe_token)
          expect(flash[:error]).to be_present
        end
      end
    end

    context "when an exception occurs" do
      before do
        allow(DayPassInteractorFactory).to receive_message_chain(:for, :call).and_raise("Test error")
      end

      it "handles the error" do
        post :create, params: valid_params
        expect(flash[:error]).to match(/An error occurred/)
      end
    end
  end

  describe "GET #code" do
    before do
      allow(controller).to receive(:current_user).and_return(regular_user)
      get :code
    end

    it "authorizes the action" do
      expect(response).to be_successful
    end
  end

  describe "POST #redeem_code" do
    before do
      allow(controller).to receive(:current_user).and_return(regular_user)
    end

    context "when code redemption is successful" do
      before do
        allow(Billing::DayPasses::RedeemCode).to receive(:call).and_return(
          OpenStruct.new(success?: true, day_pass_type: day_pass_type, day_pass_type_id: day_pass_type.id)
        )
      end

      context "when day pass type is free" do
        before do
          allow(day_pass_type).to receive(:free?).and_return(true)
          allow(Billing::DayPasses::RedeemFreeDayPass).to receive(:call).and_return(
            OpenStruct.new(success?: true)
          )
        end

        it "redeems the free day pass" do
          post :redeem_code, params: { code: "TEST123" }
          expect(flash[:success]).to eq("Day Pass redeemed!")
        end

        it "redirects to home path" do
          post :redeem_code, params: { code: "TEST123" }
          expect(response).to redirect_to(home_path)
        end
      end

      context "when day pass type is paid" do
        before do
          allow(day_pass_type).to receive(:free?).and_return(false)
        end

        it "redirects to redeem paid path" do
          post :redeem_code, params: { code: "TEST123" }
          expect(response).to redirect_to(redeem_paid_day_passes_path(code: "TEST123", day_pass_type_id: day_pass_type.id))
        end
      end
    end

    context "when code redemption fails" do
      before do
        allow(Billing::DayPasses::RedeemCode).to receive(:call).and_return(
          OpenStruct.new(success?: false, message: "Invalid code")
        )
      end

      it "sets error flash message" do
        post :redeem_code, params: { code: "INVALID" }
        expect(flash[:error]).to be_present
      end

      it "redirects to code path" do
        post :redeem_code, params: { code: "INVALID" }
        expect(response).to redirect_to(code_day_passes_path)
      end
    end
  end

  describe "GET #redeem_paid" do
    before do
      allow(controller).to receive(:current_user).and_return(regular_user)
    end

    context "when code is valid" do
      before do
        allow(Billing::DayPasses::RedeemCode).to receive(:call).and_return(
          OpenStruct.new(success?: true, day_pass_type: day_pass_type)
        )
        get :redeem_paid, params: { code: "TEST123" }
      end

      it "assigns @day_pass_type" do
        expect(assigns(:day_pass_type)).to eq(day_pass_type)
      end

      it "assigns @day_pass" do
        expect(assigns(:day_pass)).to be_a_new(DayPass)
      end

      it "includes stripe" do
        expect(assigns(:include_stripe)).to be true
      end
    end

    context "when code is invalid" do
      before do
        allow(Billing::DayPasses::RedeemCode).to receive(:call).and_return(
          OpenStruct.new(success?: false, message: "No such code")
        )
        get :redeem_paid, params: { code: "INVALID" }
      end

      it "sets error flash message" do
        expect(flash[:error]).to eq("No such code.")
      end

      it "redirects to code path" do
        expect(response).to redirect_to(code_day_passes_path)
      end
    end
  end
end