require "rails_helper"

# Web (typed-code) passwordless login — ADR 0016. Mirrors the password_resets
# two-step flow; no deep link.
RSpec.describe Operator::LoginCodesController, type: :controller do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }
  let!(:user) do
    create(:user, operator: operator, original_location: location,
                  email: "member@example.com", role: User::UNASSIGNED, email_confirmed: false)
  end

  before { request.host = "#{operator.subdomain}.lvh.me" }

  describe "POST #create" do
    it "emails a code to an existing member and advances to the verify form" do
      expect {
        post :create, params: { email: "member@example.com" }
      }.to change { ActionMailer::Base.deliveries.size }.by(1)

      expect(response).to redirect_to(login_code_verify_path(email: "member@example.com"))
      expect(user.reload.login_code_digest).to be_present
    end

    it "advances the same way for an unknown email and sends nothing (no enumeration)" do
      expect {
        post :create, params: { email: "nobody@example.com" }
      }.not_to change { ActionMailer::Base.deliveries.size }

      expect(response).to redirect_to(login_code_verify_path(email: "nobody@example.com"))
    end
  end

  describe "POST #verify" do
    it "logs the member in with a valid code and lands them in the app" do
      code = user.generate_login_code
      post :verify, params: { email: "member@example.com", code: code }

      expect(session[:user_id]).to eq(user.id)
      expect(response).to redirect_to(landing_path)
      expect(user.reload.email_confirmed?).to be(true)
    end

    it "re-renders the verify form on a wrong code without logging in" do
      user.generate_login_code
      post :verify, params: { email: "member@example.com", code: "000000" }

      expect(session[:user_id]).to be_nil
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response).to render_template(:verify)
    end
  end
end
