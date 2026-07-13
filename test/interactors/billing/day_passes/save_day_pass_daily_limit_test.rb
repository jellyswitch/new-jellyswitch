require "test_helper"

# SaveDayPass is the pass-creation authority shared by the staff/admin flows
# (web admin add/comp, mobile admin create_day_pass). It deliberately has NO
# daily-limit gate — staff can exceed the cap; gates live only at member
# self-serve entry points (see the daily-limit spec). This test pins that a
# gate never leaks into it.
class Billing::DayPasses::SaveDayPassDailyLimitTest < ActiveSupport::TestCase
  test "creates a pass past the type's daily limit (staff paths are ungated)" do
    operator = operators(:cowork_tahoe)
    location = locations(:cowork_tahoe_location)
    member   = users(:cowork_tahoe_member)
    other    = users(:cowork_tahoe_non_member)

    ActsAsTenant.with_tenant(operator) do
      dpt = DayPassType.create!(operator: operator, location: location, name: "Day Office",
                                amount_in_cents: 0, quantity: 1, available: true, daily_limit: 1)
      day = Date.current + 1
      DayPass.create!(user: other, billable: other, operator: operator, location: location,
                      day_pass_type: dpt, day: day, imported: true)

      result = Billing::DayPasses::SaveDayPass.call(
        user_id: member.id, operator: operator, location: location,
        params: { day_pass_type: dpt.id.to_s, day: day, operator_id: operator.id })

      assert result.success?, "staff pass-creation must not be blocked by the daily limit"
      assert_equal 2, dpt.day_passes.where(day: day).count
    end
  end
end
