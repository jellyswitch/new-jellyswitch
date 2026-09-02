require "rails_helper"

RSpec.describe "Embed::Concierge checkout", type: :request do
  let(:operator)   { create(:operator, concierge_enabled: true) }
  let!(:location)  { create(:location, operator: operator, visible: true, stripe_publishable_key: "pk_test_123", stripe_user_id: "acct_1") }
  let!(:pass_type) { create(:day_pass_type, operator: operator, location: location, name: "Coworking Day Pass", amount_in_cents: 2_500) }

  around do |example|
    was = Rack::Attack.enabled
    Rack::Attack.enabled = false
    example.run
    Rack::Attack.enabled = was
  end

  def url(suffix = "") = "/embed/concierge/#{operator.subdomain}/checkout#{suffix}"

  describe "GET checkout" do
    it "renders the Stripe Elements checkout for a real pass type" do
      get url, params: { day_pass_type_id: pass_type.id }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Coworking Day Pass")
      expect(response.body).to include("js.stripe.com/v3")
      # A single day pass is day-specific — the buyer picks which day.
      expect(response.body).to include("cxco-day")
      # The platform key from env config, never the DB column (which holds the
      # connected account's live-mode key).
      expect(response.body).to include(Rails.configuration.stripe[:publishable_key])
      expect(response.body).not_to include("pk_test_123")
    end

    it "tells the buyer to download and log in to the brand's app for access, rooms, and wifi" do
      get url, params: { day_pass_type_id: pass_type.id }
      expect(response.body).to include("To access the space, book meeting rooms, and connect to wifi, download and log in to the")
      expect(response.body).to include(%(data-app-name="#{operator.name}"))
    end

    it "404s when the location is not connected to Stripe" do
      location.update!(stripe_user_id: nil)
      get url, params: { day_pass_type_id: pass_type.id }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST purchase" do
    let(:params) { { day_pass_type_id: pass_type.id, location_id: location.id, email: "a@b.com", name: "A", password: "x", stripe_token: "tok_visa" } }
    let(:buyer)  { create(:user, operator: operator) }

    def stub_success
      allow(Concierge::PublicCheckout).to receive(:call)
        .and_return(double(success?: true, error: nil, message: nil, user: buyer))
    end

    it "runs the checkout orchestration and returns ok on success" do
      stub_success
      post url, params: params
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["ok"]).to be true
    end

    it "tells an unapproved buyer about the approval gate, with both store links and a summary" do
      operator.update!(approval_required: true, ios_url: "https://apps.example/i", android_url: "https://play.example/a")
      buyer.update!(approved: false)
      stub_success
      post url, params: params

      body = JSON.parse(response.body)
      expect(body["approval_pending"]).to be true
      expect(body["summary"]).to include(pass_type.name)
      expect(body["summary"]).to include(location.name)
      expect(body["app"]["ios"]).to be_present
      expect(body["app"]["android"]).to be_present
    end

    it "names the brand's app so the confirmation can say which app to install" do
      stub_success
      post url, params: params
      expect(JSON.parse(response.body)["app"]["name"]).to eq(operator.name)
    end

    it "dates a single day pass and does not ask the buyer to schedule days" do
      stub_success
      post url, params: params.merge(day: (Date.current + 2).iso8601)

      body = JSON.parse(response.body)
      expect(body["summary"]).to include((Date.current + 2).strftime("%b %-d"))
      expect(body["schedule_days"]).to be false
    end

    it "does not date a bundle and tells the buyer to schedule days in the app" do
      bundle = create(:day_pass_type, operator: operator, location: location, name: "10-Pass Bundle", quantity: 10, amount_in_cents: 20_000)
      stub_success
      post url, params: params.merge(day_pass_type_id: bundle.id)

      body = JSON.parse(response.body)
      expect(body["summary"]).to eq("10-Pass Bundle at #{[location.name, location.building_address, location.city].compact_blank.join(', ')}")
      expect(body["summary"]).not_to include(Date.current.strftime("%A"))
      expect(body["schedule_days"]).to be true
    end

    it "does not warn about approval when the operator does not require it" do
      operator.update!(approval_required: false)
      stub_success
      post url, params: params

      expect(JSON.parse(response.body)["approval_pending"]).to be false
    end

    it "surfaces a payment error from the orchestration" do
      allow(Concierge::PublicCheckout).to receive(:call)
        .and_return(double(success?: false, error: "payment", message: "Your card was declined."))
      post url, params: params
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["message"]).to eq("Your card was declined.")
    end

    it "silently drops a honeypot submission" do
      post url, params: params.merge(_hp: "bot")
      expect(response).to have_http_status(:ok)
    end

    it "passes a valid in-range day through to the orchestration" do
      day = Date.current + 3
      stub_success
      post url, params: params.merge(day: day.iso8601)
      expect(Concierge::PublicCheckout).to have_received(:call)
        .with(hash_including(day: day))
    end

    it "ignores a past or malformed day instead of failing the purchase" do
      stub_success
      post url, params: params.merge(day: "not-a-date")
      expect(Concierge::PublicCheckout).to have_received(:call)
        .with(hash_not_including(:day))

      post url, params: params.merge(day: (Date.current - 1).iso8601)
      expect(Concierge::PublicCheckout).to have_received(:call)
        .with(hash_not_including(:day)).twice
    end

    it "logs a chat Activity for a buyer who has none, so the lift metric counts them as a chatter" do
      stub_success
      expect {
        post url, params: params
      }.to change { Activity.where(user: buyer, kind: :chat).count }.by(1)

      activity = Activity.where(user: buyer, kind: :chat).last
      expect(activity.payload["source"]).to eq("concierge_checkout")
      expect(activity.payload["intent"]).to eq("day_pass")
    end

    it "does not duplicate the chat Activity when the pre-checkout capture already logged one" do
      Activity.log(user: buyer, operator: operator, kind: :chat, occurred_at: Time.current,
                   subject: location, payload: { "intent" => "day_pass" })
      stub_success
      expect {
        post url, params: params
      }.not_to change { Activity.where(user: buyer, kind: :chat).count }
    end
  end
end
