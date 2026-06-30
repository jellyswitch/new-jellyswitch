require "test_helper"

class DayPassBundleRedemptionTest < ActiveSupport::TestCase
  test "schedule_cancel is a valid kind" do
    operator = operators(:cowork_tahoe)
    ActsAsTenant.with_tenant(operator) do
      bundle = DayPassBundle.create!(
        user: users(:cowork_tahoe_admin), operator: operator,
        location: locations(:cowork_tahoe_location),
        day_pass_type: DayPassType.create!(operator: operator, location: locations(:cowork_tahoe_location),
                                           name: "5-Pack", amount_in_cents: 20000, quantity: 5, available: true, visible: true),
        quantity_purchased: 5, passes_remaining: 5, purchased_at: Time.current,
      )
      r = bundle.redemptions.build(operator: operator, kind: "schedule_cancel", redeemed_at: Time.current)
      assert r.valid?, r.errors.full_messages.to_sentence
    end
  end
end
