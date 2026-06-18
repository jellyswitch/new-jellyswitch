require "rails_helper"

RSpec.describe Api::V1::Admin::ConciergeConversationsController, type: :controller do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }
  let(:admin)    { create(:user, operator: operator, role: "admin", original_location: location, current_location: location) }
  let(:convo)    { ConciergeConversation.create!(operator: operator, location: location) }

  before do
    allow(controller).to receive(:authenticate_api_v1).and_return(true)
    allow(controller).to receive(:current_api_user).and_return(admin)
    allow(controller).to receive(:current_tenant).and_return(operator)
    allow(controller).to receive(:current_location).and_return(location)
  end

  it "lists open/staffed conversations with a last-message preview" do
    convo.messages.create!(operator: operator, role: "visitor", body: "hello there")
    get :index
    expect(response).to have_http_status(:ok)
    row = JSON.parse(response.body).find { |c| c["id"] == convo.id }
    expect(row["last_message"]).to eq("hello there")
  end

  it "replies as staff, flips status to staffed, and stamps the SLA clock" do
    post :reply, params: { id: convo.id, body: "Hi! Yes, we have parking." }
    expect(response).to have_http_status(:ok)

    convo.reload
    expect(convo.status).to eq("staffed")
    expect(convo.last_staff_message_at).to be_present
    msg = convo.messages.last
    expect(msg.role).to eq("staff")
    expect(msg.author).to eq(admin)
  end

  it "rejects an empty reply" do
    post :reply, params: { id: convo.id, body: "  " }
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "404s an unknown conversation" do
    post :reply, params: { id: 0, body: "hi" }
    expect(response).to have_http_status(:not_found)
  end
end
