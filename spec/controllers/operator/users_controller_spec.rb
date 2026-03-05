require 'rails_helper'

RSpec.describe Operator::UsersController, type: :controller do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }
  let(:admin_user) { create(:user, operator: operator, role: "superadmin", original_location: location) }
  let(:regular_user) { create(:user, operator: operator, original_location: location) }
  let(:test_user) { create(:user, operator: operator, original_location: location) }

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

      it "assigns @users" do
        expect(assigns(:users)).to include(regular_user, test_user)
      end

      it "assigns @unapproved_users" do
        unapproved_user = create(:user, operator: operator, approved: false)
        get :index
        expect(assigns(:unapproved_users)).to include(unapproved_user)
      end

      it "assigns @archived_users_count" do
        create(:user, operator: operator, archived: true)
        get :index
        expect(assigns(:archived_users_count)).to be >= 1
      end
    end
  end

  describe "GET #search" do
    before do
      allow(controller).to receive(:current_user).and_return(admin_user)
    end

    it "searches users by query" do
      allow(User).to receive(:search).with(test_user.name, fields: [:name, :email]).and_return([test_user])
      get :search, params: { query: test_user.name }
      expect(assigns(:users)).to include(test_user)
    end
  end

  describe "GET #show" do
    context "when viewing own profile" do
      before do
        allow(controller).to receive(:current_user).and_return(regular_user)
        get :show, params: { id: regular_user.id }
      end

      it "renders show template" do
        expect(response).to render_template(:show)
      end
    end

    context "when viewing other's profile" do
      before do
        allow(controller).to receive(:current_user).and_return(admin_user)
        get :show, params: { id: test_user.id }
      end

      it "renders profile template" do
        expect(response).to render_template(:profile)
      end
    end
  end

  describe "GET #new" do
    context "when user is admin" do
      before do
        allow(controller).to receive(:current_user).and_return(admin_user)
        get :new
      end

      it "assigns a new user" do
        expect(assigns(:user)).to be_a_new(User)
      end
    end
  end

  describe "POST #create" do
    let(:valid_params) do
      {
        user: {
          name: "New User",
          email: "newuser@example.com",
          password: "password123",
          password_confirmation: "password123"
        }
      }
    end

    context "when user is admin" do
      before do
        allow(controller).to receive(:current_user).and_return(admin_user)
      end

      context "with valid params" do
        it "creates a new user" do
          expect {
            post :create, params: valid_params
          }.to change(User, :count).by(1)
        end

        it "redirects to user path" do
        allow(CreateStripeCustomer).to receive(:call).and_return(double(success?: true))
          post :create, params: valid_params
          expect(response).to redirect_to(user_path(User.last))
        end
      end

      context "with invalid params" do
        let(:invalid_params) do
          { user: { email: "" } }
        end

        it "does not create a new user" do
          expect {
            post :create, params: invalid_params
          }.not_to change(User, :count)
        end

        it "renders add_member template" do
          post :create, params: invalid_params
          expect(response).to render_template(:add_member)
        end
      end
    end
  end

  describe "PUT #update" do
    let(:update_params) do
      {
        id: test_user.id,
        user: {
          name: "Updated Name"
        }
      }
    end

    before do
      allow(controller).to receive(:current_user).and_return(admin_user)
    end

    it "updates the user" do
      put :update, params: update_params
      test_user.reload
      expect(test_user.name).to eq("Updated Name")
    end

    it "redirects to user path" do
        allow(CreateStripeCustomer).to receive(:call).and_return(double(success?: true))
      put :update, params: update_params
      expect(response).to redirect_to(user_path(test_user))
    end
  end

  describe "PUT #update_password" do
    let(:password_params) do
      {
        user_id: test_user.id,
        user: {
          password: "newpassword",
          password_confirmation: "newpassword"
        }
      }
    end

    before do
      allow(controller).to receive(:current_user).and_return(admin_user)
    end

    it "updates the user's password" do
      put :update_password, params: password_params
      test_user.reload
      expect(test_user.authenticate("newpassword")).to be_truthy
    end
  end

  describe "POST #approve" do
    let(:unapproved_user) { create(:user, operator: operator, approved: false) }

    before do
      allow(controller).to receive(:current_user).and_return(admin_user)
    end

    it "approves the user" do
      post :approve, params: { user_id: unapproved_user.id }
      unapproved_user.reload
      expect(unapproved_user.approved).to be true
    end
  end

  describe "POST #unapprove" do
    before do
      allow(controller).to receive(:current_user).and_return(admin_user)
    end

    it "unapproves the user" do
      post :unapprove, params: { user_id: test_user.id }
      test_user.reload
      expect(test_user.approved).to be false
    end
  end

  describe "POST #archive" do
    before do
      allow(controller).to receive(:current_user).and_return(admin_user)
    end

    it "archives the user" do
      post :archive, params: { user_id: test_user.id }
      test_user.reload
      expect(test_user.archived).to be true
    end
  end

  describe "POST #unarchive" do
    let(:archived_user) { create(:user, operator: operator, archived: true) }

    before do
      allow(controller).to receive(:current_user).and_return(admin_user)
    end

    it "unarchives the user" do
      post :unarchive, params: { user_id: archived_user.id }
      archived_user.reload
      expect(archived_user.archived).to be false
    end
  end

  describe "POST #credit_card" do
    before do
      allow(controller).to receive(:current_user).and_return(admin_user)
    end

    it "sets user to credit card payment method" do
      post :credit_card, params: { user_id: test_user.id }
      test_user.reload
      expect(test_user.out_of_band).to be false
    end
  end

  describe "POST #out_of_band" do
    before do
      allow(controller).to receive(:current_user).and_return(admin_user)
    end

    it "sets user to out of band payment method" do
      post :out_of_band, params: { user_id: test_user.id }
      test_user.reload
      expect(test_user.out_of_band).to be true
    end
  end

  describe "POST #add_credits" do
    before do
      allow(controller).to receive(:current_user).and_return(admin_user)
    end

    it "adds credits to user" do
      initial_credits = test_user.credit_balance
      post :add_credits, params: { user_id: test_user.id, amount: 10 }
      test_user.reload
      expect(test_user.credit_balance).to eq(initial_credits + 10)
    end
  end

  describe "POST #add_childcare_reservations" do
    before do
      allow(controller).to receive(:current_user).and_return(admin_user)
    end

    it "adds childcare reservations to user" do
      initial_balance = test_user.childcare_reservation_balance
      post :add_childcare_reservations, params: { user_id: test_user.id, amount: 5 }
      test_user.reload
      expect(test_user.childcare_reservation_balance).to eq(initial_balance + 5)
    end
  end

  describe "DELETE #destroy" do
    context "when user is not an organization owner" do
      before do
        allow(controller).to receive(:current_user).and_return(admin_user)
      end

      it "deletes the user" do
        delete :destroy, params: { id: test_user.id }
        expect(test_user.reload.archived).to be true
      end
    end

    context "when user is an organization owner" do
      let!(:organization) { create(:organization, owner: test_user, operator: operator) }

      before do
        allow(controller).to receive(:current_user).and_return(admin_user)
      end

      it "does not delete the user" do
        delete :destroy, params: { id: test_user.id }
        expect(test_user.reload.archived).to be false
      end
    end
  end
end