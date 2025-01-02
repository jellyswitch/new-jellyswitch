require 'rails_helper'

RSpec.describe Operator::LocationsController, type: :controller do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }
  let(:admin_user) { create(:user, operator: operator, role: "superadmin", original_location: location) }
  let(:regular_user) { create(:user, operator: operator, original_location: location) }

  before do
    allow(controller).to receive(:current_location).and_return(location)
    request.host = "#{operator.subdomain}.lvh.me"
  end

  describe "GET #index" do
    context "when user is admin" do
      before do
        allow(controller).to receive(:current_user).and_return(admin_user)
        get :index
      end

      it "assigns @locations" do
        expect(assigns(:locations)).to eq([location])
      end
    end

    context "when user is not admin" do
      before do
        allow(controller).to receive(:current_user).and_return(regular_user)
        get :index
      end

      it "redirects to root path" do
        expect(response).to redirect_to(root_path)
      end
    end
  end

  describe "GET #show" do
    context "when user is admin" do
      before do
        allow(controller).to receive(:current_user).and_return(admin_user)
        get :show, params: { id: location.id }
      end

      it "assigns @location" do
        expect(assigns(:location)).to eq(location)
      end
    end
  end

  describe "GET #new" do
    context "when user is admin" do
      before do
        allow(controller).to receive(:current_user).and_return(admin_user)
        get :new
      end

      it "assigns a new location" do
        expect(assigns(:location)).to be_a_new(Location)
      end
    end
  end

  describe "POST #create" do
    let(:valid_params) do
      {
        location: {
          name: "New Location",
          building_address: "123 Test St",
          city: "Test City",
          state: "TS",
          zip: "12345",
          time_zone: "Pacific Time (US & Canada)",
          working_day_start: "09:00",
          working_day_end: "17:00"
        }
      }
    end

    context "when user is admin" do
      before do
        allow(controller).to receive(:current_user).and_return(admin_user)
      end

      context "with valid params" do
        it "creates a new location" do
          expect {
            post :create, params: valid_params
          }.to change(Location.unscoped, :count).by(1)
        end

        it "redirects to the created location" do
          post :create, params: valid_params
          expect(response).to redirect_to(location_path(Location.last))
        end
      end

      context "with invalid params" do
        let(:invalid_params) do
          { location: { working_day_start: nil } }
        end

        it "does not create a new location" do
          expect {
            post :create, params: invalid_params
          }.not_to change(Location.unscoped, :count)
        end

        it "renders the new template" do
          post :create, params: invalid_params
          expect(response).to render_template(:new)
        end
      end
    end
  end

  describe "GET #edit" do
    context "when user is admin" do
      before do
        allow(controller).to receive(:current_user).and_return(admin_user)
        get :edit, params: { id: location.id }
      end

      it "assigns @location" do
        expect(assigns(:location)).to eq(location)
      end
    end
  end

  describe "PUT #update" do
    let(:update_params) do
      {
        id: location.id,
        location: {
          name: "Updated Location Name"
        }
      }
    end

    context "when user is admin" do
      before do
        allow(controller).to receive(:current_user).and_return(admin_user)
      end

      context "with valid params" do
        it "updates the location" do
          put :update, params: update_params
          location.reload
          expect(location.name).to eq("Updated Location Name")
        end

        it "redirects to the location" do
          put :update, params: update_params
          expect(response).to redirect_to(location_path(location))
        end
      end

      context "with invalid params" do
        let(:invalid_update_params) do
          {
            id: location.id,
            location: { working_day_end: nil }
          }
        end

        it "does not update the location" do
          original_working_day_end = location.working_day_end
          put :update, params: invalid_update_params
          location.reload
          expect(location.working_day_end).to eq(original_working_day_end)
        end

        it "renders the new template" do
          put :update, params: invalid_update_params
          expect(response).to render_template(:new)
        end
      end
    end
  end

  describe "DELETE #destroy" do
    context "when user is admin" do
      before do
        allow(controller).to receive(:current_user).and_return(admin_user)
      end

      it "destroys the location" do
        expect {
          delete :destroy, params: { id: location.id }
        }.to change(Location.unscoped, :count).by(-1)
      end
    end
  end

  describe "POST #allow_hourly" do
    context "when user is admin" do
      before do
        allow(controller).to receive(:current_user).and_return(admin_user)
      end

      it "toggles allow_hourly setting" do
        original_value = location.allow_hourly
        post :allow_hourly, params: { location_id: location.id }
        location.reload
        expect(location.allow_hourly).to eq(!original_value)
      end

      it "redirects to location path" do
        post :allow_hourly, params: { location_id: location.id }
        expect(response).to redirect_to(location_path(location))
      end
    end
  end

  describe "POST #new_users_get_free_day_pass" do
    context "when user is admin" do
      before do
        allow(controller).to receive(:current_user).and_return(admin_user)
      end

      it "toggles new_users_get_free_day_pass setting" do
        original_value = location.new_users_get_free_day_pass
        post :new_users_get_free_day_pass, params: { location_id: location.id }
        location.reload
        expect(location.new_users_get_free_day_pass).to eq(!original_value)
      end

      it "redirects to location path" do
        post :new_users_get_free_day_pass, params: { location_id: location.id }
        expect(response).to redirect_to(location_path(location))
      end
    end
  end

  describe "POST #visible" do
    context "when user is admin" do
      before do
        allow(controller).to receive(:current_user).and_return(admin_user)
      end

      it "toggles visible setting" do
        original_value = location.visible
        post :visible, params: { location_id: location.id }
        location.reload
        expect(location.visible).to eq(!original_value)
      end

      it "redirects to location path" do
        post :visible, params: { location_id: location.id }
        expect(response).to redirect_to(location_path(location))
      end
    end
  end
end