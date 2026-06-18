require "rails_helper"

RSpec.describe "Embed::Concierge live chat", type: :request do
  let(:operator)  { create(:operator, concierge_enabled: true) }
  let!(:location) { create(:location, operator: operator, visible: true) }

  around do |example|
    was = Rack::Attack.enabled
    Rack::Attack.enabled = false
    example.run
    Rack::Attack.enabled = was
  end

  def start
    post "/embed/concierge/#{operator.subdomain}/conversations"
    JSON.parse(response.body)
  end

  context "during open hours" do
    before { allow_any_instance_of(Location).to receive(:open_now?).and_return(true) }

    it "starts a conversation, greets the visitor, and alerts staff" do
      expect { post "/embed/concierge/#{operator.subdomain}/conversations" }
        .to have_enqueued_job(SendNotificationsJob)
        .with(an_instance_of(ConciergeConversation), "ConciergeChatAlert")

      body = JSON.parse(response.body)
      expect(body["open_now"]).to be true
      expect(body["token"]).to be_present
      expect(body["messages"].first["role"]).to eq("bot")
      expect(ConciergeConversation.find_by(session_token: body["token"]).staff_alerted).to be true
    end

    it "accepts a visitor message and polls it back" do
      token = start["token"]
      post "/embed/concierge/#{operator.subdomain}/conversations/#{token}/messages", params: { body: "is there parking?" }
      expect(response).to have_http_status(:ok)

      get "/embed/concierge/#{operator.subdomain}/conversations/#{token}/messages"
      bodies = JSON.parse(response.body)["messages"].map { |m| m["body"] }
      expect(bodies).to include("is there parking?")
    end

    it "404s polling an unknown token" do
      get "/embed/concierge/#{operator.subdomain}/conversations/nope/messages"
      expect(response).to have_http_status(:not_found)
    end
  end

  context "off hours" do
    before { allow_any_instance_of(Location).to receive(:open_now?).and_return(false) }

    it "starts without greeting or alerting staff (widget falls back to capture)" do
      expect { post "/embed/concierge/#{operator.subdomain}/conversations" }
        .not_to have_enqueued_job(SendNotificationsJob)

      body = JSON.parse(response.body)
      expect(body["open_now"]).to be false
      expect(body["messages"]).to be_empty
    end
  end
end
