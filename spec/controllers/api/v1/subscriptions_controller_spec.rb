require 'rails_helper'

RSpec.describe Api::V1::SubscriptionsController, type: :controller do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }
  let(:member)   { create(:user, operator: operator, original_location: location) }

  describe "POST #cancel_now — commitment enforcement" do
    before do
      allow(controller).to receive(:authenticate_api_v1).and_return(true)
      allow(controller).to receive(:current_api_user).and_return(member)
      allow(controller).to receive(:current_tenant).and_return(operator)
      allow(controller).to receive(:current_location).and_return(location)
    end

    it "schedules cancellation at the commitment boundary instead of cancelling immediately" do
      plan = create(:plan, operator: operator, location: location, interval: "monthly", commitment_interval: 6)
      sub  = create(:subscription, plan: plan, subscribable: member, billable: member,
                    start_date: 2.months.ago.to_date, stripe_subscription_id: nil)
      allow_any_instance_of(Subscription).to receive(:set_end_date!) # stub Stripe
      expect(Billing::Subscription::CancelSubscriptionNow).not_to receive(:call)

      post :cancel_now, params: { id: sub.id }

      body = JSON.parse(response.body)
      expect(body["scheduled"]).to be true
      expect(body["ends_on"]).to be_present
      expect(sub.reload.cancelling_at_end_of_billing_period).to be true
      expect(sub.reload.active).to be true
    end

    it "cancels immediately when there is no commitment" do
      plan = create(:plan, operator: operator, location: location, commitment_interval: nil)
      sub  = create(:subscription, plan: plan, subscribable: member, billable: member, stripe_subscription_id: nil)
      expect(Billing::Subscription::CancelSubscriptionNow).to receive(:call)
        .and_return(double(success?: true))

      post :cancel_now, params: { id: sub.id }

      expect(JSON.parse(response.body)["success"]).to be true
    end
  end

  describe "#subscription_json commitment fields" do
    it "exposes in_commitment and commitment_ends_on for a committed plan" do
      plan = create(:plan, operator: operator, location: location, interval: "monthly", commitment_interval: 6)
      sub  = create(:subscription, plan: plan, subscribable: member, billable: member,
                    start_date: 2.months.ago.to_date, stripe_subscription_id: nil)

      json = controller.send(:subscription_json, sub)

      expect(json[:in_commitment]).to be true
      expect(json[:commitment_ends_on]).to be_present
    end

    it "leaves commitment fields empty when there is no commitment" do
      plan = create(:plan, operator: operator, location: location, commitment_interval: nil)
      sub  = create(:subscription, plan: plan, subscribable: member, billable: member, stripe_subscription_id: nil)

      json = controller.send(:subscription_json, sub)

      expect(json[:in_commitment]).to be false
      expect(json[:commitment_ends_on]).to be_nil
    end
  end

  describe "#subscription_json Day Pool fields" do
    it "exposes day_limit, days_used and days_left for a day-limited plan" do
      plan = create(:plan, operator: operator, location: location, has_day_limit: true, day_limit: 10)
      sub  = create(:subscription, plan: plan, subscribable: member, billable: member, stripe_subscription_id: nil)

      json = controller.send(:subscription_json, sub)

      expect(json[:day_limit]).to eq(10)
      expect(json[:days_used]).to eq(0)
      expect(json[:days_left]).to eq(10)
    end

    it "leaves the Day Pool fields nil when the plan has no day limit" do
      plan = create(:plan, operator: operator, location: location, has_day_limit: false, day_limit: 0)
      sub  = create(:subscription, plan: plan, subscribable: member, billable: member, stripe_subscription_id: nil)

      json = controller.send(:subscription_json, sub)

      expect(json[:day_limit]).to be_nil
      expect(json[:days_used]).to be_nil
    end
  end
end
