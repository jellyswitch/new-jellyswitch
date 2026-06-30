require "test_helper"

class Billing::DayPassBundles::ScheduleDayDoorTest < ActiveSupport::TestCase
  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
  end

  test "a pass scheduled for today is already covered at the door — no second burn" do
    ActsAsTenant.with_tenant(@operator) do
      member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      dpt = DayPassType.create!(operator: @operator, location: @location, name: "Pack",
                                amount_in_cents: 20000, quantity: 5, available: true, visible: true)
      bundle = DayPassBundle.create!(user: member, operator: @operator, location: @location,
                                     day_pass_type: dpt, quantity_purchased: 5, passes_remaining: 5,
                                     purchased_at: Time.current)

      # Schedule "today" (boundary): mints today's dated pass, burns one.
      Billing::DayPassBundles::ScheduleDay.call(
        user: member, location: @location, date: Date.current, performed_by: member)
      assert_equal 4, bundle.reload.passes_remaining

      # Door entry today runs ConsumeOnEntry; Guard 4 sees the existing pass → no burn.
      door = Billing::DayPassBundles::ConsumeOnEntry.call(user: member, location: @location)
      assert_equal :already_covered, door.outcome
      assert_equal 4, bundle.reload.passes_remaining, "door must not burn a second pass"
    end
  end
end
