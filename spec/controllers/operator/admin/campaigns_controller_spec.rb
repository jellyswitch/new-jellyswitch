require "rails_helper"

RSpec.describe Operator::Admin::CampaignsController, type: :controller do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }
  let(:admin_user) { create(:user, operator: operator, role: "superadmin", current_location: location, original_location: location) }
  let(:member) { create(:user, operator: operator, role: "unassigned", current_location: location, original_location: location) }

  before do
    allow(controller).to receive(:current_location).and_return(location)
    request.host = "#{operator.subdomain}.lvh.me"
  end

  describe "authorization (the controller was ungated — any member could manage campaigns)" do
    context "as a non-staff member" do
      before { allow(controller).to receive(:current_user).and_return(member) }

      it "denies GET #index" do
        get :index
        expect(response).to redirect_to(root_path)
      end

      it "denies POST #create" do
        expect {
          post :create, params: { campaign: { name: "X", campaign_type: "single" } }
        }.not_to change { Campaign.count }
        expect(response).to redirect_to(root_path)
      end

      it "denies POST #send_campaign on an existing campaign" do
        campaign = Campaign.create!(operator: operator, name: "C", campaign_type: "single", status: "draft", segment: {})
        post :send_campaign, params: { id: campaign.id }
        expect(response).to redirect_to(root_path)
        expect(campaign.reload.status).to eq("draft")
      end
    end

    context "as an admin" do
      before { allow(controller).to receive(:current_user).and_return(admin_user) }

      it "allows GET #index" do
        get :index
        expect(response).to be_successful
      end

      it "persists the interest segment on create" do
        post :create, params: { campaign: { name: "Office push", campaign_type: "single",
                                            segment: { interest_products: ["office"], interest_match: "all" } } }
        campaign = Campaign.where(operator: operator).order(:created_at).last
        expect(campaign).to be_present
        expect(campaign.segment["interest_products"]).to eq(["office"])
        expect(campaign.segment["interest_match"]).to eq("all")
      end
    end
  end
end
