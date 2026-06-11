require 'rails_helper'

RSpec.describe Api::V1::SubscriptionsController, type: :controller do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }
  let(:member)   { create(:user, operator: operator, original_location: location) }

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
