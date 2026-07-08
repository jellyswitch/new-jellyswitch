require "rails_helper"

RSpec.describe Billing::DiscountCodes::CreateStripeCoupon do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }

  before do
    allow(location).to receive(:stripe_secret_key).and_return("sk_test_x")
    allow(location).to receive(:stripe_user_id).and_return("acct_x")
  end

  it "creates the Stripe coupon with the code's duration ('forever' for recurring)" do
    code = create(:discount_code, operator: operator, duration: "forever")
    expect(Stripe::Coupon).to receive(:create)
      .with(hash_including(duration: "forever"), anything)
      .and_return(double(id: "co_recurring"))

    result = described_class.call(discount_code: code, location: location)

    expect(result.stripe_coupon_id).to eq("co_recurring")
    expect(code.reload.stripe_coupon_id).to eq("co_recurring")
  end

  it "defaults to a one-time ('once') coupon" do
    code = create(:discount_code, operator: operator, duration: "once")
    expect(Stripe::Coupon).to receive(:create)
      .with(hash_including(duration: "once"), anything)
      .and_return(double(id: "co_once"))

    described_class.call(discount_code: code, location: location)
  end

  it "reuses an already-created coupon without hitting Stripe" do
    code = create(:discount_code, operator: operator)
    code.update_column(:stripe_coupon_id, "co_existing")
    expect(Stripe::Coupon).not_to receive(:create)

    result = described_class.call(discount_code: code, location: location)

    expect(result.stripe_coupon_id).to eq("co_existing")
  end
end
