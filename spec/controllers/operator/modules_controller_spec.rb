require 'rails_helper'

RSpec.describe Operator::ModulesController, type: :controller do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }
  let(:admin_user) { create(:user, operator: operator, role: "superadmin", original_location: location) }
  let(:regular_user) { create(:user, operator: operator, original_location: location) }

  before do
    allow(controller).to receive(:current_location).and_return(location)
    request.host = "#{operator.subdomain}.lvh.me"
    allow(controller).to receive(:current_user).and_return(admin_user)
  end

  describe "GET #index" do
    it "authorizes the action" do
      get :index
      expect(response).to be_successful
    end
  end

  shared_examples "module toggle" do |action, attribute|
    describe "POST ##{action}" do
      it "toggles #{attribute}" do
        original_value = location.send(attribute)
        post action
        location.reload
        expect(location.send(attribute)).to eq(!original_value)
      end

      it "redirects to modules path" do
        post action
        expect(response).to redirect_to(modules_path)
      end

      context "when toggle fails" do
        before do
          allow(ToggleValue).to receive(:call).and_return(
            OpenStruct.new(success?: false, message: "Error")
          )
        end

        it "sets error flash message" do
          post action
          expect(flash[:error]).to be_present
        end
      end
    end
  end

  # Test each module toggle
  it_behaves_like "module toggle", :announcements, :announcements_enabled
  it_behaves_like "module toggle", :bulletin_board, :bulletin_board_enabled
  it_behaves_like "module toggle", :events, :events_enabled
  it_behaves_like "module toggle", :door_integration, :door_integration_enabled
  it_behaves_like "module toggle", :rooms, :rooms_enabled
  it_behaves_like "module toggle", :credits, :credits_enabled
  it_behaves_like "module toggle", :crm, :crm_enabled
  it_behaves_like "module toggle", :childcare, :childcare_enabled

  describe "POST #offices" do
    context "when location has no active office leases" do
      before do
        allow(location).to receive(:has_active_office_leases?).and_return(false)
      end

      it "toggles offices_enabled" do
        original_value = location.offices_enabled
        post :offices
        location.reload
        expect(location.offices_enabled).to eq(!original_value)
      end
    end

    context "when location has active office leases" do
      before do
        allow(location).to receive(:has_active_office_leases?).and_return(true)
        post :offices
      end

      it "sets error flash message" do
        expect(flash[:error]).to eq("Terminate active office leases before disabling.")
      end

      it "redirects to modules path" do
        expect(response).to redirect_to(modules_path)
      end
    end
  end

  describe "POST #reservation_credits_settings" do
    let(:valid_params) do
      {
        location_id: location.id,
        credit_cost: "10"
      }
    end

    it "updates credit cost" do
      post :reservation_credits_settings, params: valid_params
      location.reload
      expect(location.credit_cost_in_cents).to eq(1000) # $10.00 in cents
    end

    it "redirects to modules path" do
      post :reservation_credits_settings, params: valid_params
      expect(response).to redirect_to(modules_path)
    end

    context "when update fails" do
      before do
        allow_any_instance_of(Location).to receive(:update).and_return(false)
      end

      it "sets error flash message" do
        post :reservation_credits_settings, params: valid_params
        expect(flash[:error]).to eq("Something went wrong.")
      end
    end
  end

  describe "POST #childcare_reservations_settings" do
    let(:valid_params) do
      {
        location_id: location.id,
        childcare_reservation_cost: "15"
      }
    end

    it "updates childcare reservation cost" do
      post :childcare_reservations_settings, params: valid_params
      location.reload
      expect(location.childcare_reservation_cost_in_cents).to eq(1500) # $15.00 in cents
    end

    it "redirects to modules path" do
      post :childcare_reservations_settings, params: valid_params
      expect(response).to redirect_to(modules_path)
    end

    context "when update fails" do
      before do
        allow_any_instance_of(Location).to receive(:update).and_return(false)
      end

      it "sets error flash message" do
        post :childcare_reservations_settings, params: valid_params
        expect(flash[:error]).to eq("Something went wrong.")
      end
    end
  end

  describe "authorization" do
    context "when user is not authorized" do
      before do
        allow(controller).to receive(:current_user).and_return(regular_user)
      end

      it "cannot access index" do
        get :index
        expect(response).to redirect_to(root_path)
      end

      it "cannot toggle modules" do
        post :announcements
        expect(response).to redirect_to(root_path)
      end

      it "cannot update settings" do
        post :reservation_credits_settings, params: { location_id: location.id, credit_cost: "10" }
        expect(response).to redirect_to(root_path)
      end
    end
  end
end