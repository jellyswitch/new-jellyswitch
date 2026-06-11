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
end
