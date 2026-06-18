require "rails_helper"

RSpec.describe Operator::ConciergeConversationsController, type: :controller do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }
  let(:staff)    { create(:user, operator: operator, role: "admin", original_location: location, current_location: location) }
  let(:convo)    { ConciergeConversation.create!(operator: operator, location: location) }

  before do
    request.host = "#{operator.subdomain}.lvh.me"
    allow(controller).to receive(:current_location).and_return(location)
    allow(controller).to receive(:current_user).and_return(staff)
  end

  it "lists active conversations" do
    convo.messages.create!(operator: operator, role: "visitor", body: "hi")
    get :index
    expect(response).to have_http_status(:ok)
    expect(assigns(:conversations)).to include(convo)
  end

  it "replies as the staff member and flips the conversation to staffed" do
    post :reply, params: { id: convo.id, body: "Hi there! How can we help?" }

    convo.reload
    expect(convo.status).to eq("staffed")
    expect(convo.last_staff_message_at).to be_present
    expect(convo.messages.last.author).to eq(staff)
    expect(response).to redirect_to(concierge_conversation_path(convo))
  end

  it "polls new messages as JSON" do
    convo.messages.create!(operator: operator, role: "visitor", body: "any desks free?")
    get :messages, params: { id: convo.id, after: 0 }
    expect(JSON.parse(response.body).first["body"]).to eq("any desks free?")
  end

  it "blocks non-staff members" do
    member = create(:user, operator: operator, role: "unassigned")
    allow(controller).to receive(:current_user).and_return(member)
    get :index
    expect(response).to redirect_to(root_path)
  end
end
