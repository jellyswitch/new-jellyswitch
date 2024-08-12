require "rails_helper"

RSpec.describe Billing::Plans::UpdateLocalPlanPrice, type: :interactor do
  let!(:office_lease) { create(:office_lease) }

  describe "when the update is successful" do
    it "sets new price and returns plan to context" do
      result = Billing::Plans::UpdateLocalPlanPrice.call(office_lease: office_lease, new_price_in_cents: 100)

      new_plan = office_lease.subscription.plan.reload

      expect(new_plan.amount_in_cents).to eq(100)
      expect(result.plan).to eq(new_plan)
    end
  end

  describe "when the update fails" do
    let(:error_message) { "Stripe API error" }

    it "returns error message to context" do
      result = Billing::Plans::UpdateLocalPlanPrice.call(office_lease: office_lease, new_price_in_cents: -1)

      expect(result.message).to eq("Couldn't update plan price.")
    end
  end
end
