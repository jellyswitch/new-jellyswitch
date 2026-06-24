require "rails_helper"

# Passwordless Login Code endpoints — ADR 0016.
RSpec.describe Api::V1::AuthController, type: :controller do
  let!(:operator) { create(:operator, subdomain: "code-test") }
  let!(:location) { create(:location, operator: operator) }
  let!(:user) do
    create(:user, operator: operator, original_location: location,
                  email: "member@example.com", role: User::UNASSIGNED, email_confirmed: false)
  end

  before { request.headers["X-Operator-Subdomain"] = "code-test" }

  describe "POST #request_login_code" do
    it "emails a login code to an existing member and reports success" do
      expect {
        post :request_login_code, params: { subdomain: "code-test", email: "member@example.com" }
      }.to change { ActionMailer::Base.deliveries.size }.by(1)

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["success"]).to be true
      mail = ActionMailer::Base.deliveries.last
      expect(mail.to).to include("member@example.com")
      expect(mail.subject).to match(/login code/i)
      expect(user.reload.login_code_digest).to be_present
    end

    it "reports the SAME success and sends nothing for an unknown email (no enumeration)" do
      expect {
        post :request_login_code, params: { subdomain: "code-test", email: "nobody@example.com" }
      }.not_to change { ActionMailer::Base.deliveries.size }

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["success"]).to be true
    end

    it "404s on an unknown space" do
      post :request_login_code, params: { subdomain: "nope", email: "member@example.com" }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST #verify_login_code" do
    it "logs the member in with a valid code and returns the same payload as password login" do
      code = user.generate_login_code

      post :verify_login_code, params: { subdomain: "code-test", email: "member@example.com", code: code }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["token"]).to be_present
      expect(body["user"]["email"]).to eq("member@example.com")
      # The verify confirmed the email as a side-effect (the one-step payoff).
      expect(user.reload.email_confirmed?).to be(true)
    end

    it "rejects a wrong code with 401" do
      user.generate_login_code
      post :verify_login_code, params: { subdomain: "code-test", email: "member@example.com", code: "000000" }
      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects when there is no active code" do
      post :verify_login_code, params: { subdomain: "code-test", email: "member@example.com", code: "123456" }
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
