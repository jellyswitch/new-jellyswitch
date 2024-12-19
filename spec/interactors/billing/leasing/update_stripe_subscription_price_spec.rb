require "rails_helper"

RSpec.describe Billing::Leasing::UpdateStripeSubscriptionPrice, type: :interactor do
  let!(:office_lease) { create(:office_lease) }
  let!(:operator) { create(:operator) }
  let(:stripe_subscription) { double("Stripe::Subscription") }

  describe "when the update is successful" do
    it "calls update_stripe_subscription_price on the operator and set to context" do
      expect_any_instance_of(Location).to receive(:update_stripe_subscription_price).with(office_lease.subscription, 100).and_return(stripe_subscription)

      result = Billing::Leasing::UpdateStripeSubscriptionPrice.call(office_lease: office_lease, new_price_in_cents: 100, operator: operator)

      expect(result.updated_stripe_subscription).to eq(stripe_subscription)
    end
  end

  describe "when the update fails" do
    let(:error_message) { "Stripe API error" }

    before do
      allow(office_lease.location).to receive(:update_stripe_subscription_price).and_raise(StandardError.new(error_message))
    end

    it "returns error message to context" do
      result = Billing::Leasing::UpdateStripeSubscriptionPrice.call(office_lease: office_lease, new_price_in_cents: -100, operator: operator)

      expect(result.message).to eq("Failed to update Stripe subscription: #{error_message}")
    end
  end
end
