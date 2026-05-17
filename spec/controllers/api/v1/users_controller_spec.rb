require "rails_helper"

RSpec.describe Api::V1::UsersController, type: :controller do
  describe "GET #me" do
    let(:operator) { create(:operator) }
    let(:location) { create(:location, operator: operator) }
    let(:user) { create(:user, operator: operator, current_location: location, role: "superadmin", admin: true, superadmin: true) }

    before do
      ActsAsTenant.current_tenant = operator
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
  end
end
