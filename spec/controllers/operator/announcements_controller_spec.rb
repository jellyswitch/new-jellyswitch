require 'rails_helper'

RSpec.describe Operator::AnnouncementsController, type: :controller do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }
  let(:admin_user) { create(:user, operator: operator, role: "superadmin", original_location: location) }
  let(:regular_user) { create(:user, operator: operator, original_location: location) }
  let(:announcement) { create(:announcement, operator: operator, location: location, user: admin_user) }

  before do
    allow(controller).to receive(:current_location).and_return(location)
    request.host = "#{operator.subdomain}.lvh.me"
  end

  describe "GET #index" do
    context "when user is admin" do
      before do
        allow(controller).to receive(:current_user).and_return(admin_user)
        announcement # Create the announcement
        get :index
      end

      it "assigns @announcements" do
        expect(assigns(:announcements)).to include(announcement)
      end

      it "returns http success" do
        expect(response).to have_http_status(:success)
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

  describe "GET #new" do
    context "when user is admin" do
      before do
        allow(controller).to receive(:current_user).and_return(admin_user)
        get :new
      end

      it "assigns a new announcement" do
        expect(assigns(:announcement)).to be_a_new(Announcement)
      end

      it "returns http success" do
        expect(response).to have_http_status(:success)
      end
    end

    context "when user is not admin" do
      before do
        allow(controller).to receive(:current_user).and_return(regular_user)
        get :new
      end

      it "redirects to root path" do
        expect(response).to redirect_to(root_path)
      end
    end
  end

  describe "POST #create" do
    let(:valid_params) do
      {
        announcement: {
          body: "Test announcement"
        }
      }
    end

    context "when user is admin" do
      before do
        allow(controller).to receive(:current_user).and_return(admin_user)
      end

      context "with valid params" do
        it "creates a new announcement" do
          expect {
            post :create, params: valid_params
          }.to change(Announcement.unscoped, :count).by(1)
        end

        it "sets success flash message" do
          post :create, params: valid_params
          expect(flash[:success]).to match(/Announcement posted/)
        end

        it "redirects to feed items path" do
          post :create, params: valid_params
          expect(response).to redirect_to(feed_items_path)
        end
      end

      context "with invalid params" do
        before do
          allow(Announcements::Create).to receive(:call).and_return(
            OpenStruct.new(success?: false, message: "Error creating announcement")
          )
        end

        it "sets error flash message" do
          post :create, params: valid_params
          expect(flash[:error]).to be_present
        end

        it "redirects to new announcement path" do
          post :create, params: valid_params
          expect(response).to redirect_to(new_announcement_path)
        end
      end
    end

    context "when user is not admin" do
      before do
        allow(controller).to receive(:current_user).and_return(regular_user)
        post :create, params: valid_params
      end

      it "redirects to root path" do
        expect(response).to redirect_to(root_path)
      end
    end
  end
end