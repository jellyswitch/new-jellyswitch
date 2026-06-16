require 'rails_helper'

RSpec.describe Operator::DayPassBundleRestoresController, type: :controller do
  let(:operator)       { create(:operator) }
  let(:location)       { create(:location, operator: operator) }
  let(:admin)          { create(:user, operator: operator, role: "superadmin", original_location: location) }
  let(:member)         { create(:user, operator: operator, original_location: location) }
  let(:day_pass_type)  { create(:day_pass_type, operator: operator, location: location) }
  let!(:bundle)        { create(:day_pass_bundle, user: member, operator: operator, day_pass_type: day_pass_type, passes_remaining: 2) }

  before do
    allow(controller).to receive(:current_location).and_return(location)
    allow(controller).to receive(:current_user).and_return(admin)
    request.host = "#{operator.subdomain}.lvh.me"
  end

  describe "POST #create" do
    it "increments passes_remaining by 1 and logs an admin_restore redemption" do
      expect {
        post :create, params: { user_id: member.id, day_pass_bundle_id: bundle.id, reason: "accidental" }
      }.to change { bundle.reload.passes_remaining }.by(1)
        .and change(DayPassBundleRedemption, :count).by(1)

      redemption = DayPassBundleRedemption.last
      expect(redemption.kind).to eq("admin_restore")
      expect(redemption.performed_by).to eq(admin)
      expect(redemption.day_pass_bundle).to eq(bundle)
    end

    it "redirects back with a success flash" do
      post :create, params: { user_id: member.id, day_pass_bundle_id: bundle.id, reason: "accidental" }
      expect(response).to redirect_to(user_day_passes_path(member))
      expect(flash[:notice]).to be_present
    end

    it "does not let a non-manager restore a pass" do
      allow(controller).to receive(:current_user).and_return(member)
      expect {
        post :create, params: { user_id: member.id, day_pass_bundle_id: bundle.id, reason: "accidental" }
      }.not_to change { bundle.reload.passes_remaining }
    end

    it "raises RecordNotFound for a bundle belonging to a different operator (cross-tenant rejected)" do
      other_operator  = create(:operator)
      other_location  = create(:location, operator: other_operator)
      other_member    = create(:user, operator: other_operator, original_location: other_location)
      other_pass_type = create(:day_pass_type, operator: other_operator, location: other_location)
      other_bundle    = create(:day_pass_bundle, user: other_member, operator: other_operator,
                               day_pass_type: other_pass_type, passes_remaining: 3)

      expect {
        post :create, params: { user_id: member.id, day_pass_bundle_id: other_bundle.id, reason: "oops" }
      }.to raise_error(ActiveRecord::RecordNotFound)

      expect(other_bundle.reload.passes_remaining).to eq(3)
    end
  end
end
