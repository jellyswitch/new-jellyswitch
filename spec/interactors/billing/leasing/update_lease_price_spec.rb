require "rails_helper"

RSpec.describe Billing::Leasing::UpdateLeasePrice, type: :interactor do
  describe ".organize" do
    it "organizes the correct interactors in the correct order" do
      expect(described_class.organized).to eq([
        Billing::Leasing::UpdateStripeSubscriptionPrice,
        Billing::Plans::UpdateLocalPlanPrice,
      ])
    end
  end
end
