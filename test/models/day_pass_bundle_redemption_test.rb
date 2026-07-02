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

  # I2: uniqueness guard — two entry redemptions may not share a day_pass_id
  test "two entry redemptions pointing at the same DayPass are invalid" do
    operator = operators(:cowork_tahoe)
    ActsAsTenant.with_tenant(operator) do
      member = users(:cowork_tahoe_admin)
      location = locations(:cowork_tahoe_location)
      dpt = DayPassType.create!(operator: operator, location: location,
                                name: "5-Pack", amount_in_cents: 20000, quantity: 5, available: true, visible: true)
      bundle = DayPassBundle.create!(
        user: member, operator: operator, location: location, day_pass_type: dpt,
        quantity_purchased: 5, passes_remaining: 5, purchased_at: Time.current)
      day_pass = DayPass.create!(user: member, billable: member, operator: operator, location: location,
                                 day_pass_type: dpt, day: Date.current + 1, imported: true)

      bundle.redemptions.create!(operator: operator, kind: "entry",
                                 performed_by: member, day_pass: day_pass, redeemed_at: Time.current)
      dup = bundle.redemptions.build(operator: operator, kind: "entry",
                                     performed_by: member, day_pass: day_pass, redeemed_at: Time.current)
      assert_not dup.valid?, "duplicate entry redemption for same day_pass should be invalid"
      assert_includes dup.errors[:day_pass_id], "has already been taken"
    end
  end

  # I2: nil day_pass_id rows (guest/admin_restore/schedule_cancel) are unaffected by allow_nil
  test "two admin_restore redemptions with nil day_pass_id are both valid" do
    operator = operators(:cowork_tahoe)
    ActsAsTenant.with_tenant(operator) do
      member = users(:cowork_tahoe_admin)
      location = locations(:cowork_tahoe_location)
      dpt = DayPassType.create!(operator: operator, location: location,
                                name: "5-Pack", amount_in_cents: 20000, quantity: 5, available: true, visible: true)
      bundle = DayPassBundle.create!(
        user: member, operator: operator, location: location, day_pass_type: dpt,
        quantity_purchased: 5, passes_remaining: 5, purchased_at: Time.current)

      bundle.redemptions.create!(operator: operator, kind: "admin_restore",
                                 performed_by: member, day_pass: nil, redeemed_at: Time.current)
      second = bundle.redemptions.build(operator: operator, kind: "admin_restore",
                                        performed_by: member, day_pass: nil, redeemed_at: Time.current)
      assert second.valid?, "nil day_pass_id rows must not be constrained: #{second.errors.full_messages.to_sentence}"
    end
  end
end
