require "rails_helper"

RSpec.describe Api::V1::Admin::CampaignsController, type: :controller do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }
  let(:admin_user) { create(:user, operator: operator, role: "admin", current_location: location, original_location: location) }
  let(:regular_user) { create(:user, operator: operator, role: "unassigned", current_location: location, original_location: location) }

  def jwt_for(user)
    payload = { user_id: user.id, operator_id: user.operator_id, exp: 1.hour.from_now.to_i }
    JWT.encode(payload, Rails.application.secret_key_base, "HS256")
  end

  before { request.headers["X-Operator-Subdomain"] = operator.subdomain }

  describe "GET #show" do
    let(:campaign) do
      Campaign.create!(operator: operator, location: location, name: "Winter", campaign_type: "single", status: "active",
                       segment: { "interest_products" => ["office"], "interest_match" => "any" })
    end
    let!(:step) { CampaignStep.create!(campaign: campaign, position: 0, subject: "Hi", body: "Body") }

    context "as an admin" do
      before { request.headers["Authorization"] = "Bearer #{jwt_for(admin_user)}" }

      it "returns campaign detail with the interest segment and the attribution scorecard" do
        buyer = create(:user, operator: operator, original_location: location)
        CampaignSend.create!(campaign: campaign, campaign_step: step, user: buyer, status: "sent",
                             sent_at: 3.days.ago, opened: true, opened_at: 3.days.ago)
        Activity.create!(user: buyer, operator: operator, kind: "day_pass", occurred_at: 2.days.ago, subject: buyer)

        get :show, params: { id: campaign.id }
        body = JSON.parse(response.body)

        expect(response).to have_http_status(:ok)
        expect(body["name"]).to eq("Winter")
        expect(body["subject"]).to eq("Hi")
        expect(body["segment"]["interest_products"]).to eq(["office"])
        expect(body["segment"]["interest_match"]).to eq("any")
        expect(body["scorecard"]).to include("sent" => 1, "opened" => 1, "converted" => 1)
      end
    end

    context "as a non-admin" do
      before { request.headers["Authorization"] = "Bearer #{jwt_for(regular_user)}" }

      it "is forbidden" do
        get :show, params: { id: campaign.id }
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "POST #create with an interest segment" do
    before { request.headers["Authorization"] = "Bearer #{jwt_for(admin_user)}" }

    it "persists interest_products / interest_match from the mobile audience picker" do
      post :create, params: { name: "Office push", campaign_type: "single",
                              segment: { interest_products: ["office", "membership"], interest_match: "all" } }
      campaign = Campaign.where(operator: operator).order(:created_at).last
      expect(campaign.segment["interest_products"]).to eq(["office", "membership"])
      expect(campaign.segment["interest_match"]).to eq("all")
    end
  end
end
