require 'rails_helper'

RSpec.describe Operator::SetLocationController, type: :controller do
  let(:operator) { create(:operator) }
  let(:visible_location) { create(:location, operator: operator, visible: true) }
  let(:hidden_location)  { create(:location, operator: operator, visible: false) }
  let(:member) { create(:user, operator: operator, original_location: visible_location) }
  let(:admin)  { create(:user, operator: operator, role: "superadmin", original_location: visible_location) }

  before do
    request.host = "#{operator.subdomain}.lvh.me"
    ActsAsTenant.current_tenant = operator
  end

  # Members may only switch to a *visible* location; staff may target a hidden
  # (deprecated/staff-only) one. The raw Location.find let a member land on a
  # hidden location by id — mirrors the mobile switch_location gate.
  describe "PUT #update" do
    context "as a non-staff member" do
      before { allow(controller).to receive(:current_user).and_return(member) }

      it "switches to a visible location" do
        put :update, params: { location: { id: visible_location.id } }
        expect(flash[:error]).to be_blank
        expect(member.reload.current_location).to eq(visible_location)
      end

      it "does NOT switch to a hidden location" do
        put :update, params: { location: { id: hidden_location.id } }
        expect(flash[:error]).to be_present
        expect(member.reload.current_location).not_to eq(hidden_location)
      end
    end

    context "as staff (superadmin)" do
      before { allow(controller).to receive(:current_user).and_return(admin) }

      it "can switch to a hidden location" do
        put :update, params: { location: { id: hidden_location.id } }
        expect(flash[:error]).to be_blank
        expect(admin.reload.current_location).to eq(hidden_location)
      end
    end
  end
end
