require "rails_helper"

RSpec.describe Api::V1::Admin::FeedController, type: :controller do
  let(:operator) { create(:operator) }
  let(:admin)    { create(:user, operator: operator, role: "admin", name: "Adam Admin") }
  let(:member)   { create(:user, operator: operator, role: "unassigned", approved: true, name: "Jane Member") }
  let(:teammate) { create(:user, operator: operator, role: "general-manager", name: "Greg GM") }

  before do
    allow(controller).to receive(:authenticate_api_v1).and_return(true)
    allow(controller).to receive(:current_api_user).and_return(admin)
    allow(controller).to receive(:current_tenant).and_return(operator)
    allow(controller).to receive(:current_location).and_return(nil)
  end

  describe "POST #create — customer tag cross-post" do
    it "mirrors a feed post that tags a member onto the member's record" do
      member; teammate
      expect {
        post :create, params: { body: "Great chat with @Jane Member, upgrade likely." }
      }.to change { Note.where(notable: member).count }.by(1)

      note = Note.where(notable: member).last
      expect(note.author).to eq(admin)
      expect(note.body.to_plain_text).to include("upgrade likely")
    end

    it "does not cross-post when only a staff teammate is tagged" do
      teammate
      expect {
        post :create, params: { body: "Heads up @Greg GM please follow up." }
      }.not_to change(Note, :count)
    end
  end

  describe "GET #index — day pass bundle purchase" do
    let(:buyer)     { create(:user, operator: operator, role: "unassigned", approved: false, name: "Penny Pack") }
    let(:pack_type) { create(:day_pass_type, operator: operator, name: "5-Pack", quantity: 5, amount_in_cents: 20_000) }
    let(:bundle) do
      create(:day_pass_bundle, user: buyer, day_pass_type: pack_type, operator: operator,
                               quantity_purchased: 5, passes_remaining: 5)
    end

    before do
      FeedItem.create!(
        operator: operator, user: buyer,
        blob: { type: "day-pass-bundle", day_pass_bundle_id: bundle.id, user_name: buyer.name,
                message: "#{buyer.name} purchased a 5-Pack" }
      )
    end

    subject(:item) do
      get :index
      JSON.parse(response.body).find { |i| i["type"] == "day-pass-bundle" }
    end

    it "emits the pack price as amount, the approval fields, the type name and pack size" do
      expect(item).to be_present
      expect(item["amount"]).to eq(20_000)            # flat pack price (ADR 0009)
      expect(item["requires_approval"]).to be true    # new buyer approvable from the feed
      expect(item["user_approved"]).to be false
      expect(item["user_id"]).to eq(buyer.id)
      expect(item["day_pass_type"]).to eq("5-Pack")
      expect(item["action_text"]).to include("5-Pack")
    end
  end
end
