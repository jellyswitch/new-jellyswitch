require "rails_helper"

RSpec.describe Api::V1::UsersController, type: :controller do
  describe "GET #me" do
    let(:operator) { create(:operator) }
    let(:location) { create(:location, operator: operator) }
    let(:user) { create(:user, operator: operator, current_location: location, role: "superadmin", admin: true, superadmin: true) }

    before do
      ActsAsTenant.current_tenant = operator
      # Bypass JWT auth (no token in a controller spec); we stub the user directly.
      allow(controller).to receive(:authenticate_api_v1).and_return(true)
      allow(controller).to receive(:current_api_user).and_return(user)
    end

    it "includes admin and superadmin booleans alongside role" do
      get :me
      body = JSON.parse(response.body)
      expect(body["role"]).to eq("superadmin")
      expect(body["admin"]).to eq(true)
      expect(body["superadmin"]).to eq(true)
    end

    it "returns admin=false for a plain member" do
      member = create(:user, operator: operator, current_location: location, role: "member", admin: false, superadmin: false)
      allow(controller).to receive(:current_api_user).and_return(member)
      get :me
      body = JSON.parse(response.body)
      expect(body["role"]).to eq("member")
      expect(body["admin"]).to eq(false)
      expect(body["superadmin"]).to eq(false)
    end

    it "exposes email-confirmation state so the app can show a verify nudge" do
      member = create(:user, operator: operator, current_location: location,
                             role: User::UNASSIGNED, email_confirmed: false)
      allow(controller).to receive(:current_api_user).and_return(member)
      get :me
      body = JSON.parse(response.body)
      expect(body["email_confirmed"]).to eq(false)
      expect(body["needs_email_confirmation"]).to eq(true)
    end
  end
end
