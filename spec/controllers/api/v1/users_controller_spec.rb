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

  # A member must not be able to escape an office lease or a minimum-term
  # commitment by deleting their account (which used to deactivate ALL active
  # subs — lease-backed and committed included). Only an admin/host ends those.
  describe "DELETE #destroy_account" do
    let(:operator) { create(:operator) }
    let(:location) { create(:location, operator: operator) }
    let(:member)   { create(:user, operator: operator, original_location: location) }

    before do
      ActsAsTenant.current_tenant = operator
      allow(controller).to receive(:authenticate_api_v1).and_return(true)
      allow(controller).to receive(:current_api_user).and_return(member)
      allow(controller).to receive(:current_tenant).and_return(operator)
      allow(controller).to receive(:current_location).and_return(location)
    end

    it "deletes the account for a plain member (cancels subs, archives)" do
      plan = create(:plan, operator: operator, location: location, commitment_interval: nil)
      sub  = create(:subscription, plan: plan, subscribable: member, billable: member, stripe_subscription_id: nil)

      delete :destroy_account

      expect(JSON.parse(response.body)["success"]).to be true
      expect(sub.reload.active).to be false
      expect(member.reload.archived).to be true
    end

    it "blocks deletion when the member backs an office lease" do
      lease_plan = create(:plan, operator: operator, location: location, plan_type: "lease", amount_in_cents: 90000)
      lease_sub  = create(:subscription, plan: lease_plan, subscribable: member, billable: member, stripe_subscription_id: nil)

      delete :destroy_account

      expect(response).to have_http_status(:forbidden)
      expect(lease_sub.reload.active).to be true
      expect(member.reload.archived).to be false
    end

    it "blocks deletion when the member is inside a minimum-term commitment" do
      plan = create(:plan, operator: operator, location: location, interval: "monthly", commitment_interval: 6)
      sub  = create(:subscription, plan: plan, subscribable: member, billable: member,
                    start_date: 2.months.ago.to_date, stripe_subscription_id: nil)

      delete :destroy_account

      expect(response).to have_http_status(:forbidden)
      expect(sub.reload.active).to be true
      expect(member.reload.archived).to be false
    end
  end
end
