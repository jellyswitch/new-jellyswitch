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
      # The platform key from env config, never the DB column (which holds the
      # connected account's live-mode key).
      expect(response.body).to include(Rails.configuration.stripe[:publishable_key])
      expect(response.body).not_to include("pk_test_123")
    end

    it "404s when the location is not connected to Stripe" do
      location.update!(stripe_user_id: nil)
      get url, params: { day_pass_type_id: pass_type.id }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST purchase" do
    let(:params) { { day_pass_type_id: pass_type.id, location_id: location.id, email: "a@b.com", name: "A", password: "x", stripe_token: "tok_visa" } }

    it "runs the checkout orchestration and returns ok on success" do
      allow(Concierge::PublicCheckout).to receive(:call)
        .and_return(double(success?: true, error: nil, message: nil))
      post url, params: params
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["ok"]).to be true
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
  end
end
