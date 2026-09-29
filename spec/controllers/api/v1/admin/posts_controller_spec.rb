require "rails_helper"

RSpec.describe Api::V1::Admin::PostsController, type: :controller do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator, name: "Cowork Tahoe") }
  let(:admin)    { create(:user, operator: operator, role: "superadmin", name: "Adam Admin") }
  let(:member)   { create(:user, operator: operator, role: "unassigned", approved: true, name: "Drew Member") }

  before do
    allow(controller).to receive(:authenticate_api_v1).and_return(true)
    allow(controller).to receive(:current_api_user).and_return(admin)
    allow(controller).to receive(:current_tenant).and_return(operator)
    allow(controller).to receive(:current_location).and_return(location)
  end

  describe "DELETE #destroy" do
    let!(:post_record) { create(:post, user: member, location: location, title: "Fundraiser") }

    it "removes a post on the admin's location along with its replies" do
      PostReply.create!(post: post_record, user: member, content: "Sounds fun")

      expect {
        delete :destroy, params: { id: post_record.id }
      }.to change(Post, :count).by(-1).and change(PostReply, :count).by(-1)

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["success"]).to be true
    end

    it "404s for a post on a location the admin is not viewing and leaves it in place" do
      other_location = create(:location, operator: operator, name: "Elsewhere")
      other_post = create(:post, user: member, location: other_location, title: "Not yours")

      expect {
        delete :destroy, params: { id: other_post.id }
      }.not_to change(Post, :count)

      expect(response).to have_http_status(:not_found)
    end
  end
end
