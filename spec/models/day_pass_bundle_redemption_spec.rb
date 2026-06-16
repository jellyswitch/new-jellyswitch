require "rails_helper"

RSpec.describe DayPassBundleRedemption do
  let(:operator) { create(:operator) }
  let(:bundle) do
    user = create(:user, operator: operator)
    DayPassBundle.create!(user: user, billable: user, operator: operator,
                          day_pass_type: create(:day_pass_type, operator: operator, quantity: 5),
                          quantity_purchased: 5, passes_remaining: 5, purchased_at: Time.current)
  end

  it "requires a valid kind" do
    r = DayPassBundleRedemption.new(day_pass_bundle: bundle, operator: operator, kind: "bogus", redeemed_at: Time.current)
    expect(r).not_to be_valid
    expect(r.errors[:kind]).to be_present
  end

  it "accepts entry/guest/admin_restore" do
    %w[entry guest admin_restore].each do |k|
      r = DayPassBundleRedemption.new(day_pass_bundle: bundle, operator: operator, kind: k, redeemed_at: Time.current)
      expect(r).to be_valid, "expected kind=#{k} to be valid"
    end
  end
end
