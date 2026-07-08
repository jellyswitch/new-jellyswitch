require "rails_helper"

RSpec.describe DiscountCode do
  describe "duration" do
    it "defaults to 'once' (first payment only)" do
      expect(create(:discount_code).duration).to eq("once")
    end

    it "accepts 'once' and 'forever'" do
      expect(build(:discount_code, duration: "once")).to be_valid
      expect(build(:discount_code, duration: "forever")).to be_valid
    end

    it "rejects an unknown duration" do
      expect(build(:discount_code, duration: "repeating")).not_to be_valid
    end
  end

  # A Stripe coupon bakes in amount/percent AND duration at creation and we cache
  # its id — so editing any of those must drop the stale coupon so a fresh one is
  # minted (otherwise a member keeps getting the old discount/duration).
  describe "stripe coupon cache invalidation" do
    def code_with_coupon(**attrs)
      code = create(:discount_code, **attrs)
      code.update_column(:stripe_coupon_id, "co_cached")
      code
    end

    it "drops the cached coupon when duration changes" do
      code = code_with_coupon(duration: "once")
      expect { code.update!(duration: "forever") }.to change { code.reload.stripe_coupon_id }.from("co_cached").to(nil)
    end

    it "drops the cached coupon when the discount value changes" do
      code = code_with_coupon(discount_value: 10)
      expect { code.update!(discount_value: 25) }.to change { code.reload.stripe_coupon_id }.to(nil)
    end

    it "drops the cached coupon when the discount type changes" do
      code = code_with_coupon(discount_type: "percent_off", discount_value: 10)
      expect { code.update!(discount_type: "amount_off", discount_value: 500) }.to change { code.reload.stripe_coupon_id }.to(nil)
    end

    it "keeps the cached coupon when an unrelated field changes" do
      code = code_with_coupon
      code.update!(active: false)
      expect(code.reload.stripe_coupon_id).to eq("co_cached")
    end
  end
end
