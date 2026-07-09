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

      it "computes the attribution scorecard on #show" do
        campaign = Campaign.create!(operator: operator, location: location, name: "S", campaign_type: "single", status: "active", segment: {})
        step = CampaignStep.create!(campaign: campaign, position: 0, subject: "Hi", body: "x")
        buyer = create(:user, operator: operator, original_location: location)
        CampaignSend.create!(campaign: campaign, campaign_step: step, user: buyer, status: "sent",
                             sent_at: 3.days.ago, opened: true, opened_at: 3.days.ago)
        Activity.create!(user: buyer, operator: operator, kind: "day_pass", occurred_at: 2.days.ago, subject: buyer)

        get :show, params: { id: campaign.id }
        expect(response).to be_successful
        expect(assigns(:scorecard)).to include(sent: 1, opened: 1, converted: 1)
      end
    end
  end
end
