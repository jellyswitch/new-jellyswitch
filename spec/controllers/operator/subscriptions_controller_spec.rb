require 'rails_helper'

RSpec.describe Operator::SubscriptionsController, type: :controller do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }
  let(:admin_user) { create(:user, operator: operator, role: "superadmin", original_location: location) }
  let(:regular_user) { create(:user, operator: operator, original_location: location) }
  let(:plan) { create(:plan, operator: operator, location: location) }
  let(:plan_category) { create(:plan_category, operator: operator, location: location) }
  let(:subscription) { create(:subscription, plan: plan, subscribable: regular_user, billable: regular_user) }
  let(:lease_plan) { create(:plan, operator: operator, location: location, plan_type: "lease") }
  let(:lease_subscription) { create(:subscription, plan: lease_plan, subscribable: regular_user, billable: regular_user) }

  before do
    allow(controller).to receive(:current_location).and_return(location)
    request.host = "#{operator.subdomain}.lvh.me"
  end

  describe "GET #index" do
    before do
      allow(controller).to receive(:current_user).and_return(regular_user)
    end

    context "without plan_category_id" do
      before { get :index }

      it "assigns default plans" do
        expect(assigns(:plans)).to include(plan)
      end
    end

    context "with plan_category_id" do
      let(:categorized_plan) { create(:plan, operator: operator, location: location, plan_category: plan_category) }

      before do
        categorized_plan
        get :index, params: { plan_category_id: plan_category.id }
      end

      it "assigns filtered plans" do
        expect(assigns(:plans)).to include(categorized_plan)
      end
    end
  end

  describe "GET #new" do
    before do
      allow(controller).to receive(:current_user).and_return(regular_user)
      get :new, params: { plan_id: plan.id }
    end

    it "assigns a new subscription" do
      expect(assigns(:subscription)).to be_a_new(Subscription)
    end

    it "assigns the selected plan" do
      expect(assigns(:plan)).to eq(plan)
    end
  end

  describe "POST #create" do
    let(:stripe_token) { "tok_visa" }
    let(:subscription_params) do
      {
        subscription: { plan_id: plan.id },
        stripeToken: stripe_token
      }
    end

    before do
      allow(controller).to receive(:current_user).and_return(regular_user)
    end

    context "with valid params" do
      before do
        allow(Billing::Subscription::UpdatePaymentAndCreateSubscription)
          .to receive(:call).and_return(OpenStruct.new(success?: true))
      end

      it "creates a new subscription" do
        post :create, params: subscription_params
        expect(flash[:success]).to match(/Welcome to/)
      end

      it "redirects to root path" do
        post :create, params: subscription_params
        expect(response).to redirect_to(root_path)
      end
    end

    context "with invalid params" do
      before do
        allow(Billing::Subscription::UpdatePaymentAndCreateSubscription)
          .to receive(:call).and_return(OpenStruct.new(success?: false, message: "Error"))
      end

      it "sets error flash message" do
        post :create, params: subscription_params
        expect(flash[:error]).to be_present
      end
    end
  end

  describe "GET #edit" do
    before do
      allow(controller).to receive(:current_user).and_return(regular_user)
      get :edit, params: { id: subscription.id }
    end

    it "assigns the subscription" do
      expect(assigns(:subscription)).to eq(subscription)
    end
  end

  describe "PUT #update" do
    let(:new_plan) { create(:plan, operator: operator, location: location) }
    let(:update_params) do
      {
        id: subscription.id,
        subscription: { plan_id: new_plan.id }
      }
    end

    before do
      allow(controller).to receive(:current_user).and_return(regular_user)
    end

    context "with valid params" do
      before do
        allow(UpdateMembership)
          .to receive(:call).and_return(OpenStruct.new(success?: true))
      end

      it "updates the subscription" do
        put :update, params: update_params
        expect(flash[:success]).to be_present
      end

      context "when admin" do
        before do
          allow(controller).to receive(:current_user).and_return(admin_user)
        end

        it "redirects to user path" do
          put :update, params: update_params
          expect(response).to redirect_to(user_path(subscription.subscribable))
        end
      end

      context "when regular user" do
        it "redirects to user memberships path" do
          put :update, params: update_params
          expect(response).to redirect_to(user_memberships_path(regular_user))
        end
      end
    end

    context "with invalid params" do
      before do
        allow(UpdateMembership)
          .to receive(:call).and_return(OpenStruct.new(success?: false, message: "Error"))
      end

      it "sets error flash message" do
        put :update, params: update_params
        expect(flash[:error]).to be_present
      end
    end

    # An office lease is a fixed-term agreement: a member must not be able to
    # downgrade the subscription backing one (Byron Whetzel escaped Office Lease
    # #3430 by switching to Flex this way). Only staff may, via the lease flow.
    context "when the subscription backs an office lease" do
      let(:lease_update_params) do
        { id: lease_subscription.id, subscription: { plan_id: new_plan.id } }
      end

      it "blocks a member and does not switch the plan" do
        expect(UpdateMembership).not_to receive(:call)
        put :update, params: lease_update_params
        expect(flash[:error]).to match(/office lease/i)
        expect(response).to redirect_to(user_memberships_path(regular_user))
      end

      it "allows staff (admin) to switch it" do
        allow(controller).to receive(:current_user).and_return(admin_user)
        allow(UpdateMembership).to receive(:call).and_return(OpenStruct.new(success?: true))
        put :update, params: lease_update_params
        expect(UpdateMembership).to have_received(:call)
        expect(flash[:success]).to be_present
      end
    end
  end

  describe "DELETE #destroy" do
    before do
      allow(controller).to receive(:current_user).and_return(regular_user)
    end

    context "when cancellation is successful" do
      before do
        allow(SetSubscriptionForCancellation)
          .to receive(:call).and_return(OpenStruct.new(success?: true))
      end

      it "cancels the subscription" do
        delete :destroy, params: { id: subscription.id }
        expect(flash[:success]).to match(/scheduled for cancellation/)
      end
    end

    context "when cancellation fails" do
      before do
        allow(SetSubscriptionForCancellation)
          .to receive(:call).and_return(OpenStruct.new(success?: false, message: "Error"))
      end

      it "sets error flash message" do
        delete :destroy, params: { id: subscription.id }
        expect(flash[:error]).to be_present
      end
    end

    context "when the subscription backs an office lease" do
      it "blocks a member from cancelling it" do
        expect(SetSubscriptionForCancellation).not_to receive(:call)
        delete :destroy, params: { id: lease_subscription.id }
        expect(flash[:error]).to match(/office lease/i)
      end
    end
  end

  describe "DELETE #destroy_subscription_now" do
    before do
      allow(controller).to receive(:current_user).and_return(regular_user)
    end

    context "when immediate cancellation is successful" do
      before do
        allow(Billing::Subscription::CancelSubscriptionNow)
          .to receive(:call).and_return(OpenStruct.new(success?: true))
      end

      it "cancels the subscription immediately" do
        delete :destroy_subscription_now, params: { id: subscription.id }
        expect(flash[:success]).to match(/cancelled/)
      end
    end

    context "when immediate cancellation fails" do
      before do
        allow(Billing::Subscription::CancelSubscriptionNow)
          .to receive(:call).and_return(OpenStruct.new(success?: false, message: "Error"))
      end

      it "sets error flash message" do
        delete :destroy_subscription_now, params: { id: subscription.id }
        expect(flash[:error]).to be_present
      end
    end

    context "when the subscription backs an office lease" do
      it "blocks a member from cancelling it immediately" do
        expect(Billing::Subscription::CancelSubscriptionNow).not_to receive(:call)
        delete :destroy_subscription_now, params: { id: lease_subscription.id }
        expect(flash[:error]).to match(/office lease/i)
      end
    end
  end

  # A member inside a minimum-term commitment (TLH) must not be able to end
  # early on either web cancel button — both should schedule the end at the
  # commitment boundary. Staff cancel normally.
  describe "minimum-term commitment enforcement" do
    let(:committed_plan) { create(:plan, operator: operator, location: location, interval: "monthly", commitment_interval: 6) }
    let(:committed_sub) do
      create(:subscription, plan: committed_plan, subscribable: regular_user, billable: regular_user,
             start_date: 2.months.ago.to_date, stripe_subscription_id: nil)
    end

    before do
      allow(controller).to receive(:current_user).and_return(regular_user)
      allow_any_instance_of(Subscription).to receive(:set_end_date!) # stub Stripe
    end

    it "DELETE #destroy schedules at the commitment boundary instead of a period-end cancel" do
      expect(SetSubscriptionForCancellation).not_to receive(:call)
      delete :destroy, params: { id: committed_sub.id }
      expect(flash[:notice]).to match(/committed through/i)
      expect(committed_sub.reload.cancelling_at_end_of_billing_period).to be true
    end

    it "DELETE #destroy_subscription_now schedules at the commitment boundary instead of an immediate cancel" do
      expect(Billing::Subscription::CancelSubscriptionNow).not_to receive(:call)
      delete :destroy_subscription_now, params: { id: committed_sub.id }
      expect(flash[:notice]).to match(/committed through/i)
      expect(committed_sub.reload.cancelling_at_end_of_billing_period).to be true
    end

    context "when staff cancels a committed member's subscription" do
      before { allow(controller).to receive(:current_user).and_return(admin_user) }

      it "cancels normally (no commitment hold for staff)" do
        allow(SetSubscriptionForCancellation).to receive(:call).and_return(OpenStruct.new(success?: true))
        expect_any_instance_of(Subscription).not_to receive(:schedule_commitment_cancellation!)
        delete :destroy, params: { id: committed_sub.id }
        expect(SetSubscriptionForCancellation).to have_received(:call)
      end
    end
  end

  describe "error handling" do
    before do
      allow(controller).to receive(:current_user).and_return(regular_user)
    end

    context "when an exception occurs" do
      before do
        allow_any_instance_of(Subscription).to receive(:save).and_raise("Test error")
      end

      it "handles the error and sets flash message" do
        post :create, params: { subscription: { plan_id: plan.id } }
        expect(flash[:error]).to match(/Cannot update payment/)
      end
    end
  end

  describe "authorization" do
    context "when user is not authorized" do
      let(:other_user) { create(:user, operator: operator, original_location: location) }
      let(:other_subscription) { create(:subscription, plan: plan, subscribable: other_user, billable: other_user) }

      before do
        allow(controller).to receive(:current_user).and_return(regular_user)
      end

      it "prevents access to another user's subscription" do
        get :edit, params: { id: other_subscription.id }
        expect(response).to redirect_to(root_path)
      end
    end
  end
end