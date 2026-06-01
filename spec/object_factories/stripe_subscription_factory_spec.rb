require "rails_helper"

RSpec.describe StripeSubscriptionFactory do
  let(:location) { instance_double("Location") }
  let(:lease) { instance_double("OfficeLease") }

  def subscription_with(billable_oob:, subscribable_oob:)
    instance_double(
      "Subscription",
      billable: double(out_of_band?: billable_oob),
      subscribable: double(out_of_band?: subscribable_oob),
    )
  end

  it "returns an in-band subscription when neither party is out of band" do
    subscription = subscription_with(billable_oob: false, subscribable_oob: false)
    result = described_class.for(subscription, location, lease)
    expect(result).to be_a(StripeSubscription::InBand)
  end

  it "returns an out-of-band subscription when the billable is out of band" do
    subscription = subscription_with(billable_oob: true, subscribable_oob: false)
    result = described_class.for(subscription, location, lease)
    expect(result).to be_a(StripeSubscription::OutOfBand)
  end

  it "returns an out-of-band subscription when the org (subscribable) is out of band even if the billing contact is not" do
    subscription = subscription_with(billable_oob: false, subscribable_oob: true)
    result = described_class.for(subscription, location, lease)
    expect(result).to be_a(StripeSubscription::OutOfBand)
  end
end
