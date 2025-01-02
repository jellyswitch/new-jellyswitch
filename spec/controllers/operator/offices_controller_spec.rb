require 'rails_helper'

RSpec.describe Operator::OfficesController, type: :controller do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }
  let(:admin_user) { create(:user, operator: operator, role: "superadmin", original_location: location) }
  let(:regular_user) { create(:user, operator: operator, original_location: location) }
  let!(:office) { create(:office, operator: operator, location: location) }
  let!(:office_with_lease) { create(:office, :with_active_lease, operator: operator, location: location) }

  before do
    allow(controller).to receive(:current_location).and_return(location)
    request.host = "#{operator.subdomain}.lvh.me"
  end

  describe "GET #index" do
    before do
      allow(controller).to receive(:current_user).and_return(admin_user)
      get :index
    end

    it "assigns @offices" do
      expect(assigns(:offices)).to include(office_with_lease)
    end

    it "assigns @available_offices" do
      expect(assigns(:available_offices)).to include(office)
    end

    it "assigns @upcoming_renewals" do
      expect(assigns(:upcoming_renewals)).to be_present
    end

    it "assigns @archived_offices" do
      archived_office = create(:office, operator: operator, location: location, visible: false)
      get :index
      expect(assigns(:archived_offices)).to include(archived_office)
    end
  end

  describe "GET #show" do
    before do
      allow(controller).to receive(:current_user).and_return(admin_user)
      get :show, params: { id: office.id }
    end

    it "assigns @office" do
      expect(assigns(:office)).to eq(office)
    end
  end

  describe "GET #new" do
    before do
      allow(controller).to receive(:current_user).and_return(admin_user)
      get :new
    end

    it "assigns a new office" do
      expect(assigns(:office)).to be_a_new(Office)
    end
  end

  describe "POST #create" do
    let(:valid_params) do
      {
        office: {
          name: "New Office",
          description: "Test Description",
          capacity: 4,
          square_footage: 100,
          visible: true
        }
      }
    end

    before do
      allow(controller).to receive(:current_user).and_return(admin_user)
    end

    context "with valid params" do
      it "creates a new office" do
        expect {
          post :create, params: valid_params
        }.to change(Office, :count).by(1)
      end

      it "redirects to the created office" do
        post :create, params: valid_params
        expect(response).to redirect_to(office_path(Office.last))
      end

      it "sets flash notice" do
        post :create, params: valid_params
        expect(flash[:notice]).to be_present
      end
    end
  end

  describe "GET #edit" do
    before do
      allow(controller).to receive(:current_user).and_return(admin_user)
      get :edit, params: { id: office.id }
    end

    it "assigns @office" do
      expect(assigns(:office)).to eq(office)
    end
  end

  describe "PUT #update" do
    let(:update_params) do
      {
        id: office.id,
        office: {
          name: "Updated Office Name"
        }
      }
    end

    before do
      allow(controller).to receive(:current_user).and_return(admin_user)
    end

    context "with valid params" do
      it "updates the office" do
        put :update, params: update_params
        office.reload
        expect(office.name).to eq("Updated Office Name")
      end

      it "redirects to the office" do
        put :update, params: update_params
        expect(response).to redirect_to(office_path(office))
      end

      it "sets flash notice" do
        put :update, params: update_params
        expect(flash[:notice]).to be_present
      end
    end
  end

  describe "DELETE #destroy" do
    before do
      allow(controller).to receive(:current_user).and_return(admin_user)
    end

    context "when office has no active lease" do
      it "destroys the office" do
        office
        expect {
          delete :destroy, params: { id: office.id }
        }.to change(Office, :count).by(-1)
      end

      it "redirects to offices index" do
        delete :destroy, params: { id: office.id }
        expect(response).to redirect_to(offices_path)
      end

      it "sets flash notice" do
        delete :destroy, params: { id: office.id }
        expect(flash[:notice]).to be_present
      end
    end

    context "when office has active lease" do
      it "does not destroy the office" do
        office_with_lease
        expect {
          delete :destroy, params: { id: office_with_lease.id }
        }.not_to change(Office, :count)
      end
    end
  end

  describe "GET #available" do
    before do
      allow(controller).to receive(:current_user).and_return(admin_user)
      get :available
    end

    it "assigns @offices with available offices" do
      expect(assigns(:offices)).to include(office)
      expect(assigns(:offices)).not_to include(office_with_lease)
    end
  end

  describe "GET #upcoming_renewals" do
    before do
      allow(controller).to receive(:current_user).and_return(admin_user)
      get :upcoming_renewals
    end

    it "assigns @offices with offices having upcoming renewals" do
      expect(assigns(:offices)).to be_present
    end
  end

  describe "GET #archived" do
    let(:archived_office) { create(:office, operator: operator, location: location, visible: false) }

    before do
      allow(controller).to receive(:current_user).and_return(admin_user)
      archived_office
      get :archived
    end

    it "assigns @offices with archived offices" do
      expect(assigns(:offices)).to include(archived_office)
    end
  end

  describe "authorization" do
    context "when user is not authorized" do
      before do
        allow(controller).to receive(:current_user).and_return(regular_user)
      end

      it "restricts access to index" do
        get :index
        expect(response).to redirect_to(root_path)
      end

      it "restricts access to new" do
        get :new
        expect(response).to redirect_to(root_path)
      end

      it "restricts access to create" do
        post :create, params: { office: { name: "Test" } }
        expect(response).to redirect_to(root_path)
      end

      it "restricts access to edit" do
        get :edit, params: { id: office.id }
        expect(response).to redirect_to(root_path)
      end

      it "restricts access to update" do
        put :update, params: { id: office.id, office: { name: "Test" } }
        expect(response).to redirect_to(root_path)
      end

      it "restricts access to destroy" do
        delete :destroy, params: { id: office.id }
        expect(response).to redirect_to(root_path)
      end
    end
  end

  describe "photo handling" do
    let(:photo) { fixture_file_upload('spec/fixtures/test.jpg', 'image/jpeg') }
    let(:photo_params) do
      {
        id: office.id,
        office: {
          photo: photo
        }
      }
    end

    before do
      allow(controller).to receive(:current_user).and_return(admin_user)
    end

    it "allows photo upload" do
      put :update, params: photo_params
      office.reload
      expect(office.photo).to be_attached
    end
  end
end