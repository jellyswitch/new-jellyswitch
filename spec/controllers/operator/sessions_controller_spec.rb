require "rails_helper"

# Signup spam-hardening, task #1: soften the login gate.
#
# We used to HARD-BLOCK unconfirmed members from web login (bouncing them back
# to /login with "verify your email"), which stranded real signups like Tim
# Flanagan who never clicked the confirmation link. The mobile/API path never
# blocked them at all, so the two were inconsistent. New behavior: let an
# unconfirmed member log in, and surface a persistent "verify your email" nudge
# (rendered in the operator layout) instead of slamming the door.
RSpec.describe Operator::SessionsController, type: :controller do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }

  before do
    request.host = "#{operator.subdomain}.lvh.me"
  end

  def login!(email:, password: "password123")
    post :create, params: { session: { email: email, password: password } }
  end

  describe "POST #create with an unconfirmed member" do
    let!(:user) do
      create(:user, operator: operator, original_location: location,
                    email: "unconfirmed@example.com", password: "password123",
                    email_confirmed: false, role: User::UNASSIGNED, approved: true)
    end

    it "logs them in instead of blocking" do
      login!(email: "unconfirmed@example.com")
      expect(session[:user_id]).to eq(user.id)
    end

    it "does not bounce them back to the login page with a verify-email error" do
      login!(email: "unconfirmed@example.com")
      expect(response).not_to redirect_to(login_path)
      expect(flash[:error]).to be_blank
    end

    it "redirects into the app (landing)" do
      login!(email: "unconfirmed@example.com")
      expect(response).to redirect_to(landing_path)
    end
  end

  describe "POST #create with a confirmed member (regression)" do
    let!(:user) do
      create(:user, operator: operator, original_location: location,
                    email: "confirmed@example.com", password: "password123",
                    email_confirmed: true, role: User::UNASSIGNED, approved: true)
    end

    it "still logs in normally" do
      login!(email: "confirmed@example.com")
      expect(session[:user_id]).to eq(user.id)
      expect(response).to redirect_to(landing_path)
    end
  end

  describe "POST #create with a bad password" do
    let!(:user) do
      create(:user, operator: operator, original_location: location,
                    email: "unconfirmed@example.com", password: "password123",
                    email_confirmed: false, role: User::UNASSIGNED)
    end

    it "still rejects invalid credentials" do
      login!(email: "unconfirmed@example.com", password: "wrong")
      expect(session[:user_id]).to be_nil
      expect(response).to redirect_to(login_path)
    end
  end
end
