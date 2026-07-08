require 'rails_helper'

RSpec.describe Operator::PauseMembershipsController, type: :controller do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }
  let(:admin_user) { create(:user, operator: operator, role: "superadmin", original_location: location) }
  let(:regular_user) { create(:user, operator: operator, original_location: location) }
  let(:other_user) { create(:user, operator: operator, original_location: location) }
  let(:plan) { create(:plan, operator: operator, location: location) }
  let(:subscription) { create(:subscription, plan: plan, subscribable: regular_user, billable: regular_user) }

  before do
    allow(controller).to receive(:current_location).and_return(location)
    request.host = "#{operator.subdomain}.lvh.me"
  end

  # Before the pause?/unpause? authorize guard, this controller did a global
  # Subscription.find(params[:id]) with no owner check, so any authenticated
  # member could pause/unpause ANY subscription by id (cross-member/tenant).
  describe "POST #create (pause)" do
    before { allow(CreatePause).to receive(:call).and_return(OpenStruct.new(success?: true)) }

    context "when the owning member pauses their own subscription" do
      before { allow(controller).to receive(:current_user).and_return(regular_user) }

      it "pauses it" do
        post :create, params: { id: subscription.id, resumes_at: "30" }
        expect(CreatePause).to have_received(:call)
        expect(flash[:success]).to be_present
      end
    end

    context "when a different member targets someone else's subscription (IDOR)" do
      before { allow(controller).to receive(:current_user).and_return(other_user) }

      it "does not pause and is not authorized" do
        expect(CreatePause).not_to receive(:call)
        post :create, params: { id: subscription.id, resumes_at: "30" }
        expect(response).to have_http_status(:redirect)
      end
    end

    context "when staff pauses a member's subscription" do
      before { allow(controller).to receive(:current_user).and_return(admin_user) }

      it "pauses it" do
        post :create, params: { id: subscription.id, resumes_at: "30" }
        expect(CreatePause).to have_received(:call)
      end
    end
  end

  describe "DELETE #destroy (unpause)" do
    before { allow(DestroyPause).to receive(:call).and_return(OpenStruct.new(success?: true)) }

    context "when the owning member unpauses their own subscription" do
      before { allow(controller).to receive(:current_user).and_return(regular_user) }

      it "unpauses it" do
        delete :destroy, params: { id: subscription.id }
        expect(DestroyPause).to have_received(:call)
        expect(flash[:success]).to be_present
      end
    end

    context "when a different member targets someone else's subscription (IDOR)" do
      before { allow(controller).to receive(:current_user).and_return(other_user) }

      it "does not unpause and is not authorized" do
        expect(DestroyPause).not_to receive(:call)
        delete :destroy, params: { id: subscription.id }
        expect(response).to have_http_status(:redirect)
      end
    end
  end
end
