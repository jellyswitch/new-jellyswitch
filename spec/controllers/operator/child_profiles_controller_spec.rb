require 'rails_helper'

RSpec.describe Operator::ChildProfilesController, type: :controller do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }
  let(:admin_user) { create(:user, operator: operator, role: "superadmin", original_location: location) }
  let(:regular_user) { create(:user, operator: operator, original_location: location) }
  let(:child_profile) { create(:child_profile, user: regular_user) }

  before do
    allow(controller).to receive(:current_location).and_return(location)
    request.host = "#{operator.subdomain}.lvh.me"
  end

  describe "GET #index" do
    context "when user is admin" do
      before do
        allow(controller).to receive(:current_user).and_return(admin_user)
        child_profile # Create the child profile
        get :index
      end

      it "assigns @child_profiles with all profiles" do
        expect(assigns(:child_profiles)).to include(child_profile)
      end
    end

    context "when user is regular user" do
      before do
        allow(controller).to receive(:current_user).and_return(regular_user)
        child_profile # Create the child profile
        get :index
      end

      it "assigns @child_profiles with user's profiles only" do
        other_user_profile = create(:child_profile, user: create(:user, operator: operator))
        expect(assigns(:child_profiles)).to include(child_profile)
        expect(assigns(:child_profiles)).not_to include(other_user_profile)
      end
    end
  end

  describe "GET #new" do
    before do
      allow(controller).to receive(:current_user).and_return(regular_user)
      get :new
    end

    it "assigns a new child profile" do
      expect(assigns(:child_profile)).to be_a_new(ChildProfile)
    end

    it "associates the new profile with current user" do
      expect(assigns(:child_profile).user).to eq(regular_user)
    end
  end

  describe "POST #create" do
    before do
      allow(controller).to receive(:current_user).and_return(regular_user)
    end

    let(:valid_params) do
      {
        child_profile: {
          name: "Test Child",
          birthday: Date.current - 5.years,
          notes: "Test notes"
        }
      }
    end

    context "with valid params" do
      it "creates a new child profile" do
        expect {
          post :create, params: valid_params
        }.to change(ChildProfile, :count).by(1)
      end

      it "sets success flash message" do
        post :create, params: valid_params
        expect(flash[:success]).to eq("Profile added.")
      end

      it "redirects to child profile path" do
        post :create, params: valid_params
        expect(response).to redirect_to(child_profile_path(ChildProfile.last))
      end
    end
  end

  describe "GET #edit" do
    context "when user owns the profile" do
      before do
        allow(controller).to receive(:current_user).and_return(regular_user)
        get :edit, params: { id: child_profile.id }
      end

      it "assigns @child_profile" do
        expect(assigns(:child_profile)).to eq(child_profile)
      end
    end

    context "when user doesn't own the profile" do
      let(:other_user) { create(:user, operator: operator) }

      before do
        allow(controller).to receive(:current_user).and_return(other_user)

      end

      it "raises error" do
        expect {
          get :edit, params: { id: child_profile.id }
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end

  describe "PUT #update" do
    before do
      allow(controller).to receive(:current_user).and_return(regular_user)
    end

    let(:update_params) do
      {
        id: child_profile.id,
        child_profile: {
          name: "Updated Name",
          notes: "Updated notes"
        }
      }
    end

    context "with valid params" do
      it "updates the child profile" do
        put :update, params: update_params
        child_profile.reload
        expect(child_profile.name).to eq("Updated Name")
      end

      it "sets success flash message" do
        put :update, params: update_params
        expect(flash[:success]).to eq("Profile updated.")
      end

      it "redirects to child profile path" do
        put :update, params: update_params
        expect(response).to redirect_to(child_profile_path(child_profile))
      end
    end
  end

  describe "GET #show" do
    context "when user owns the profile" do
      before do
        allow(controller).to receive(:current_user).and_return(regular_user)
        get :show, params: { id: child_profile.id }
      end

      it "assigns @child_profile" do
        expect(assigns(:child_profile)).to eq(child_profile)
      end
    end

    context "when user is admin" do
      before do
        allow(controller).to receive(:current_user).and_return(admin_user)
        get :show, params: { id: child_profile.id }
      end

      it "assigns @child_profile" do
        expect(assigns(:child_profile)).to eq(child_profile)
      end
    end
  end
end