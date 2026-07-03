require "rails_helper"

RSpec.describe Operator::EmailConfirmationsController, type: :controller do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }
  let!(:user) do
    create(:user, operator: operator, original_location: location,
                  email: "unconfirmed@example.com", role: User::UNASSIGNED, email_confirmed: false)
  end

  before do
    request.host = "#{operator.subdomain}.lvh.me"
    # Don't actually send mail in the spec.
    allow_any_instance_of(User).to receive(:send_confirmation_email)
  end

  describe "POST #resend" do
    it "resends and returns to the login page by default" do
      post :resend, params: { email: "unconfirmed@example.com" }
      expect(response).to redirect_to(login_path)
      expect(flash[:success]).to be_present
    end

    it "returns a logged-in member to a safe internal path (banner resend)" do
      post :resend, params: { email: "unconfirmed@example.com", return_to: "/account" }
      expect(response).to redirect_to("/account")
    end

    it "ignores an off-site return_to (no open redirect)" do
      post :resend, params: { email: "unconfirmed@example.com", return_to: "https://evil.example.com/phish" }
      expect(response).to redirect_to(login_path)
    end

    it "ignores a protocol-relative return_to (no open redirect)" do
      post :resend, params: { email: "unconfirmed@example.com", return_to: "//evil.example.com" }
      expect(response).to redirect_to(login_path)
    end
  end
end
