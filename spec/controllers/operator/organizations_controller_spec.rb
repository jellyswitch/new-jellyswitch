require 'rails_helper'

RSpec.describe Operator::OrganizationsController, type: :controller do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }
  let(:admin_user) { create(:user, operator: operator, role: "superadmin", original_location: location) }
  let(:regular_user) { create(:user, operator: operator, original_location: location) }
  let(:organization) { create(:organization, operator: operator, location: location) }
  let(:owner) { create(:user, operator: operator, original_location: location) }

  before do
    allow(controller).to receive(:current_location).and_return(location)
    request.host = "#{operator.subdomain}.lvh.me"
  end

  describe "GET #index" do
    before do
      allow(controller).to receive(:current_user).and_return(admin_user)
      organization
      get :index
    end

    it "assigns @organizations" do
      expect(assigns(:organizations)).to include(organization)
    end

    it "assigns @archived_organizations" do
      archived_org = create(:organization, operator: operator, location: location, visible: false)
      get :index
      expect(assigns(:archived_organizations)).to include(archived_org)
    end
  end

  describe "GET #show" do
    before do
      allow(controller).to receive(:current_user).and_return(admin_user)
      get :show, params: { id: organization.id }
    end

    it "assigns @organization" do
      expect(assigns(:organization)).to eq(organization)
    end
  end

  describe "GET #new" do
    before do
      allow(controller).to receive(:current_user).and_return(admin_user)
      get :new
    end

    it "assigns a new organization" do
      expect(assigns(:organization)).to be_a_new(Organization)
    end
  end

  describe "POST #create" do
    let(:valid_params) do
      {
        organization: {
          name: "New Organization",
          website: "http://example.com",
          owner_id: owner.id
        }
      }
    end

    before do
      allow(controller).to receive(:current_user).and_return(admin_user)
    end

    context "with valid params" do
      it "creates a new organization" do
        expect {
          post :create, params: valid_params
        }.to change(Organization, :count).by(1)
      end

      it "redirects to the created organization" do
        post :create, params: valid_params
        expect(response).to redirect_to(organization_path(Organization.last))
      end

      it "sets flash notice" do
        post :create, params: valid_params
        expect(flash[:notice]).to be_present
      end
    end

    context "with invalid params" do
      before do
        allow(CreateOrganization)
          .to receive(:call).and_return(OpenStruct.new(success?: false, message: "Error"))
      end

      it "renders new template" do
        post :create, params: { organization: { name: "" } }
        expect(response).to render_template(:new)
      end
    end
  end

  describe "GET #edit" do
    before do
      allow(controller).to receive(:current_user).and_return(admin_user)
      get :edit, params: { id: organization.id }
    end

    it "assigns @organization" do
      expect(assigns(:organization)).to eq(organization)
    end

    it "includes stripe" do
      expect(assigns(:include_stripe)).to be true
    end
  end

  describe "PUT #update" do
    let(:new_billing_contact) { create(:user, operator: operator, original_location: location) }
    let(:update_params) do
      {
        id: organization.id,
        organization: {
          name: "Updated Organization",
          billing_contact_id: new_billing_contact.id
        }
      }
    end

    before do
      allow(controller).to receive(:current_user).and_return(admin_user)
    end

    context "with valid params" do
      before do
        allow(UpdateOrganization)
          .to receive(:call).and_return(OpenStruct.new(success?: true))
      end

      it "updates the organization" do
        put :update, params: update_params
        expect(flash[:notice]).to be_present
      end

      it "redirects to the organization" do
        put :update, params: update_params
        expect(response).to redirect_to(organization_path(organization))
      end
    end

    context "with invalid params" do
      before do
        allow(UpdateOrganization)
          .to receive(:call).and_return(OpenStruct.new(success?: false, message: "Error"))
      end

      it "renders edit template" do
        put :update, params: { id: organization.id, organization: { name: "" } }
        expect(response).to render_template(:edit)
      end
    end
  end

  describe "DELETE #destroy" do
    before do
      allow(controller).to receive(:current_user).and_return(admin_user)
    end

    context "when organization can be deleted" do
      it "destroys the organization" do
        organization # Create the organization
        expect {
          delete :destroy, params: { id: organization.id }
        }.to change(Organization, :count).by(-1)
      end

      it "redirects to organizations index" do
        delete :destroy, params: { id: organization.id }
        expect(response).to redirect_to(organizations_path)
      end
    end

    context "when organization cannot be deleted" do
      before do
        allow_any_instance_of(Organization).to receive(:destroy).and_return(false)
      end

      it "redirects to organization path" do
        delete :destroy, params: { id: organization.id }
        expect(response).to redirect_to(organization_path(organization))
      end
    end
  end

  describe "POST #credit_card" do
    before do
      allow(controller).to receive(:current_user).and_return(admin_user)
      allow_any_instance_of(Organization).to receive(:card_added).and_return(true)
    end

    it "updates organization payment method to credit card" do
      post :credit_card, params: { organization_id: organization.id }
      organization.reload
      expect(organization.out_of_band).to be false
    end

    it "redirects to organization path" do
      post :credit_card, params: { organization_id: organization.id }
      expect(response).to redirect_to(organization_path(organization))
    end
  end

  describe "POST #out_of_band" do
    before do
      allow(controller).to receive(:current_user).and_return(admin_user)
    end

    it "updates organization payment method to out of band" do
      post :out_of_band, params: { organization_id: organization.id }
      organization.reload
      expect(organization.out_of_band).to be true
    end

    it "redirects to organization path" do
      post :out_of_band, params: { organization_id: organization.id }
      expect(response).to redirect_to(organization_path(organization))
    end
  end

  describe "GET #billing" do
    before do
      allow(controller).to receive(:current_user).and_return(admin_user)
      get :billing, params: { organization_id: organization.id }
    end

    it "assigns @organization" do
      expect(assigns(:organization)).to eq(organization)
    end

    it "includes stripe" do
      expect(assigns(:include_stripe)).to be true
    end
  end

  describe "GET #payment_method" do
    before do
      allow(controller).to receive(:current_user).and_return(admin_user)
      get :payment_method, params: { organization_id: organization.id }
    end

    it "assigns @organization" do
      expect(assigns(:organization)).to eq(organization)
    end
  end

  describe "GET #members" do
    before do
      allow(controller).to receive(:current_user).and_return(admin_user)
      get :members, params: { organization_id: organization.id }
    end

    it "assigns @organization" do
      expect(assigns(:organization)).to eq(organization)
    end
  end

  describe "GET #leases" do
    before do
      allow(controller).to receive(:current_user).and_return(admin_user)
      get :leases, params: { organization_id: organization.id }
    end

    it "assigns @organization" do
      expect(assigns(:organization)).to eq(organization)
    end
  end

  describe "GET #invoices" do
    before do
      allow(controller).to receive(:current_user).and_return(admin_user)
      get :invoices, params: { organization_id: organization.id }
    end

    it "assigns @organization" do
      expect(assigns(:organization)).to eq(organization)
    end
  end

  describe "GET #ltv" do
    before do
      allow(controller).to receive(:current_user).and_return(admin_user)
      get :ltv, params: { organization_id: organization.id }
    end

    it "assigns @organization" do
      expect(assigns(:organization)).to eq(organization)
    end

    it "assigns @months" do
      expect(assigns(:months)).to be_present
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

      it "restricts access to create" do
        post :create, params: { organization: { name: "Test" } }
        expect(response).to redirect_to(root_path)
      end

      it "restricts access to edit" do
        get :edit, params: { id: organization.id }
        expect(response).to redirect_to(root_path)
      end
    end
  end

  describe "error handling" do
    before do
      allow(controller).to receive(:current_user).and_return(admin_user)
    end

    it "handles errors in create" do
      allow(CreateOrganization).to receive(:call).and_raise("Test error")
      post :create, params: { organization: { name: "Test" } }
      expect(flash[:error]).to match(/An error occurred/)
    end

    it "handles errors in update" do
      allow(UpdateOrganization).to receive(:call).and_raise("Test error")
      put :update, params: { id: organization.id, organization: { name: "Test" } }
      expect(flash[:error]).to match(/An error occurred/)
    end
  end
end