require 'rails_helper'

RSpec.describe Operator::DayPassTypesController, type: :controller do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }
  let(:admin_user) { create(:user, operator: operator, role: "superadmin", original_location: location) }
  let(:regular_user) { create(:user, operator: operator, original_location: location) }
  let(:day_pass_type) { create(:day_pass_type, operator: operator, location: location) }

  before do
    allow(controller).to receive(:current_location).and_return(location)
    request.host = "#{operator.subdomain}.lvh.me"
    allow(controller).to receive(:current_user).and_return(admin_user)
  end

  describe "GET #index" do
    before do
      day_pass_type
      get :index
    end

    it "assigns @day_pass_types" do
      expect(assigns(:day_pass_types)).to include(day_pass_type)
    end
  end

  describe "GET #show" do
    before { get :show, params: { id: day_pass_type.id } }

    it "assigns @day_pass_type" do
      expect(assigns(:day_pass_type)).to eq(day_pass_type)
    end
  end

  describe "GET #new" do
    before { get :new }

    it "assigns a new day pass type" do
      expect(assigns(:day_pass_type)).to be_a_new(DayPassType)
    end
  end

  describe "POST #create" do
    let(:valid_params) do
      {
        day_pass_type: {
          name: "Test Pass",
          amount_in_cents: 2500,
          code: "TEST123",
          always_allow_building_access: true,
          description: "Test description"
        }
      }
    end

    context "with valid params" do
      before do
        allow(CreateDayPassType).to receive(:call).and_return(
          OpenStruct.new(success?: true, day_pass_type: day_pass_type)
        )
      end

      it "creates a new day pass type" do
        post :create, params: valid_params
        expect(flash[:success]).not_to be_present # Success is handled by redirect
      end

      context "with add_day_pass_type_and_add_another param" do
        it "redirects to new day pass type path" do
          post :create, params: valid_params.merge(add_day_pass_type_and_add_another: true)
          expect(response).to redirect_to(new_day_pass_type_path)
        end
      end

      context "without add_day_pass_type_and_add_another param" do
        it "redirects to day pass type path" do
          post :create, params: valid_params
          expect(response).to redirect_to(day_pass_type_path(day_pass_type))
        end
      end
    end

    context "with invalid params" do
      before do
        allow(CreateDayPassType).to receive(:call).and_return(
          OpenStruct.new(success?: false, message: "Error", day_pass_type: DayPassType.new)
        )
      end

      it "sets error flash message" do
        post :create, params: valid_params
        expect(flash[:error]).to be_present
      end

      it "renders new template" do
        post :create, params: valid_params
        expect(response).to render_template(:new)
      end
    end
  end

  describe "PUT #update" do
    let(:update_params) do
      {
        id: day_pass_type.id,
        day_pass_type: {
          code: "NEWCODE",
          amount_in_cents: 3000
        }
      }
    end

    context "with valid params" do
      it "updates the day pass type" do
        put :update, params: update_params
        day_pass_type.reload
        expect(day_pass_type.code).to eq("NEWCODE")
      end

      it "redirects to day pass type path" do
        put :update, params: update_params
        expect(response).to redirect_to(day_pass_type_path(day_pass_type))
      end
    end

    context "with invalid params" do
      let(:invalid_params) do
        {
          id: day_pass_type.id,
          day_pass_type: { name: "" }
        }
      end

      before do
        allow_any_instance_of(DayPassType).to receive(:update).and_return(false)
      end

      it "renders edit template" do
        put :update, params: invalid_params
        expect(response).to render_template(:edit)
      end
    end
  end

  describe "DELETE #destroy" do
    it "archives the day pass type" do
      delete :destroy, params: { id: day_pass_type.id }
      day_pass_type.reload
      expect(day_pass_type.available).to be false
    end

    it "redirects to day pass types url" do
      delete :destroy, params: { id: day_pass_type.id }
      expect(response).to redirect_to(day_pass_types_url)
    end
  end

  describe "POST #visible" do
    it "toggles visible setting" do
      original_value = day_pass_type.visible
      post :visible, params: { day_pass_type_id: day_pass_type.id }
      day_pass_type.reload
      expect(day_pass_type.visible).to eq(!original_value)
    end

    it "redirects to day pass type path" do
      post :visible, params: { day_pass_type_id: day_pass_type.id }
      expect(response).to redirect_to(day_pass_type_path(day_pass_type))
    end

    context "when toggle fails" do
      before do
        allow(ToggleValue).to receive(:call).and_return(
          OpenStruct.new(success?: false, message: "Error")
        )
      end

      it "sets error flash message" do
        post :visible, params: { day_pass_type_id: day_pass_type.id }
        expect(flash[:error]).to be_present
      end
    end
  end

  describe "POST #always_allow_building_access" do
    it "toggles always_allow_building_access setting" do
      original_value = day_pass_type.always_allow_building_access
      post :always_allow_building_access, params: { day_pass_type_id: day_pass_type.id }
      day_pass_type.reload
      expect(day_pass_type.always_allow_building_access).to eq(!original_value)
    end

    it "redirects to day pass type path" do
      post :always_allow_building_access, params: { day_pass_type_id: day_pass_type.id }
      expect(response).to redirect_to(day_pass_type_path(day_pass_type))
    end

    context "when toggle fails" do
      before do
        allow(ToggleValue).to receive(:call).and_return(
          OpenStruct.new(success?: false, message: "Error")
        )
      end

      it "sets error flash message" do
        post :always_allow_building_access, params: { day_pass_type_id: day_pass_type.id }
        expect(flash[:error]).to be_present
      end
    end
  end

  describe "POST #available" do
    it "toggles available setting" do
      original_value = day_pass_type.available
      post :available, params: { day_pass_type_id: day_pass_type.id }
      day_pass_type.reload
      expect(day_pass_type.available).to eq(!original_value)
    end

    it "redirects to day pass type path" do
      post :available, params: { day_pass_type_id: day_pass_type.id }
      expect(response).to redirect_to(day_pass_type_path(day_pass_type))
    end

    context "when toggle fails" do
      before do
        allow(ToggleValue).to receive(:call).and_return(
          OpenStruct.new(success?: false, message: "Error")
        )
      end

      it "sets error flash message" do
        post :available, params: { day_pass_type_id: day_pass_type.id }
        expect(flash[:error]).to be_present
      end
    end
  end
end