require 'rails_helper'

RSpec.describe Operator::DoorsController, type: :controller do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }
  let(:admin_user) { create(:user, operator: operator, role: "superadmin", original_location: location) }
  let(:regular_user) { create(:user, operator: operator, original_location: location) }
  let!(:door) { create(:door, operator: operator, location: location) }

  before do
    allow(controller).to receive(:current_location).and_return(location)
    request.host = "#{operator.subdomain}.lvh.me"
  end

  describe "GET #index" do
    before do
      allow(controller).to receive(:current_user).and_return(admin_user)
      door # Create the door
      get :index
    end

    it "assigns @doors" do
      expect(assigns(:doors)).to include(door)
    end

    it "excludes private doors for non-admin users" do
      private_door = create(:door, operator: operator, location: location, private: true)
      allow(controller).to receive(:current_user).and_return(regular_user)
      get :index
      expect(assigns(:doors)).not_to include(private_door)
    end

    it "includes doors where private is nil for non-admin users" do
      nil_private_door = create(:door, operator: operator, location: location, name: "Nil Door")
      nil_private_door.update_column(:private, nil)
      allow(controller).to receive(:current_user).and_return(regular_user)
      get :index
      expect(assigns(:doors)).to include(nil_private_door)
    end
  end

  describe "GET #show" do
    before do
      allow(controller).to receive(:current_user).and_return(admin_user)
    end

    it "assigns @door" do
      get :show, params: { id: door.id }
      expect(assigns(:door)).to eq(door)
    end

    it "assigns @punches with pagination" do
      create(:door_punch, door: door, operator: operator)
      get :show, params: { id: door.id }
      expect(assigns(:punches)).to be_present
      expect(assigns(:pagy)).to be_present
    end
  end

  describe "GET #new" do
    before do
      allow(controller).to receive(:current_user).and_return(admin_user)
      get :new
    end

    it "assigns a new door" do
      expect(assigns(:door)).to be_a_new(Door)
    end
  end

  describe "POST #create" do
    let(:valid_params) do
      {
        door: {
          name: "Test Door",
          kisi_id: "123",
          private: false
        }
      }
    end

    before do
      allow(controller).to receive(:current_user).and_return(admin_user)
    end

    context "with valid params" do
      it "creates a new door" do
        expect {
          post :create, params: valid_params
        }.to change(Door, :count).by(1)
      end

      it "redirects to the door path" do
        post :create, params: valid_params
        expect(response).to redirect_to(door_path(Door.last))
      end

      it "sets flash notice" do
        post :create, params: valid_params
        expect(flash[:notice]).to be_present
      end
    end

    context "with invalid params" do
      before do
        allow_any_instance_of(Door).to receive(:save).and_return(false)
      end

      it "renders new template" do
        post :create, params: { door: { name: "" } }
        expect(response).to render_template(:new)
      end
    end

    context "when an exception occurs" do
      before do
        allow_any_instance_of(Door).to receive(:save).and_raise("Test error")
      end

      it "handles the error" do
        post :create, params: valid_params
        expect(flash[:error]).to match(/An error occurred/)
      end
    end
  end

  describe "GET #edit" do
    before do
      allow(controller).to receive(:current_user).and_return(admin_user)
      get :edit, params: { id: door.id }
    end

    it "assigns @door" do
      expect(assigns(:door)).to eq(door)
    end
  end

  describe "PUT #update" do
    let(:update_params) do
      {
        id: door.id,
        door: {
          name: "Updated Door Name"
        }
      }
    end

    before do
      allow(controller).to receive(:current_user).and_return(admin_user)
    end

    context "with valid params" do
      it "updates the door" do
        put :update, params: update_params
        door.reload
        expect(door.name).to eq("Updated Door Name")
      end

      it "redirects to doors path" do
        put :update, params: update_params
        expect(response).to redirect_to(doors_path(door))
      end
    end

    context "with invalid params" do
      before do
        allow_any_instance_of(Door).to receive(:save).and_return(false)
      end

      it "renders edit template" do
        put :update, params: { id: door.id, door: { name: "" } }
        expect(response).to render_template(:edit)
      end
    end

    context "when an exception occurs" do
      before do
        allow_any_instance_of(Door).to receive(:update).and_raise("Test error")
      end

      it "handles the error" do
        put :update, params: update_params
        expect(flash[:error]).to match(/An error occurred/)
      end
    end
  end

  describe "DELETE #destroy" do
    before do
      allow(controller).to receive(:current_user).and_return(admin_user)
      door # Create the door
    end

    it "destroys the door" do
      expect {
        delete :destroy, params: { id: door.id }
      }.to change(Door, :count).by(-1)
    end

    it "redirects to doors path" do
      delete :destroy, params: { id: door.id }
      expect(response).to redirect_to(doors_path)
    end

    it "sets flash notice" do
      delete :destroy, params: { id: door.id }
      expect(flash[:notice]).to be_present
    end
  end

  describe "POST #open" do
    before do
      allow(controller).to receive(:current_user).and_return(admin_user)
    end

    it "creates a door punch" do
      expect {
        post :open, params: { door_id: door.id }
      }.to change(DoorPunch, :count).by(1)
    end

    it "enqueues OpenDoorJob" do
      expect(OpenDoorJob).to receive(:perform_later).with(door, admin_user)
      post :open, params: { door_id: door.id }
    end

    context "with HTML format" do
      it "redirects to home path" do
        post :open, params: { door_id: door.id }
        expect(response).to redirect_to(home_path)
      end

      context "with untethered iOS request" do
        before do
          allow(controller).to receive(:untethered_ios_request?).and_return(true)
        end

        it "redirects to home path" do
          post :open, params: { door_id: door.id }
          expect(response).to redirect_to(home_path)
        end
      end
    end

    context "with JS format" do
      it "renders open template" do
        post :open, params: { door_id: door.id }, format: :js
        expect(response).to render_template(:open)
      end
    end
  end

  describe "GET #keys" do
    before do
      allow(controller).to receive(:current_user).and_return(admin_user)
      get :keys
    end

    it "assigns @doors" do
      expect(assigns(:doors)).to be_present
    end

    context "as an approved member with active subscription" do
      let(:member_user) { create(:user, operator: operator, original_location: location, approved: true) }

      before do
        plan = create(:plan, operator: operator, location: location)
        create(:subscription, subscribable: member_user, billable: member_user, plan: plan,
               start_date: 1.month.ago, pending: false)
        allow(controller).to receive(:current_user).and_return(member_user)
      end

      it "allows access to the keys page" do
        get :keys
        expect(response).not_to have_http_status(:forbidden)
        expect(assigns(:doors)).to be_present
      end

      it "excludes private doors" do
        private_door = create(:door, operator: operator, location: location, private: true)
        get :keys
        expect(assigns(:doors)).to include(door)
        expect(assigns(:doors)).not_to include(private_door)
      end

      it "includes doors where private is nil" do
        nil_private_door = create(:door, operator: operator, location: location, name: "Nil Door")
        nil_private_door.update_column(:private, nil)
        get :keys
        expect(assigns(:doors)).to include(nil_private_door)
      end
    end

    context "when door_integration_enabled is false" do
      before do
        location.update!(door_integration_enabled: false)
        allow(controller).to receive(:current_user).and_return(admin_user)
      end

      it "still allows access since keys? does not check enabled?" do
        get :keys
        expect(response).not_to have_http_status(:forbidden)
      end
    end
  end
end