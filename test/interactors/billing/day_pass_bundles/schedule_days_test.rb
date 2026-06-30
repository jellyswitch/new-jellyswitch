require "test_helper"

class Billing::DayPassBundles::ScheduleDaysTest < ActiveSupport::TestCase
  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
  end

  def make_bundle(remaining:)
    dpt = DayPassType.create!(operator: @operator, location: @location, name: "Pack",
                              amount_in_cents: 20000, quantity: 5, available: true, visible: true)
    DayPassBundle.create!(user: @member, operator: @operator, location: @location, day_pass_type: dpt,
                          quantity_purchased: 5, passes_remaining: remaining, purchased_at: Time.current)
  end

  test "schedules every requested day and decrements once per day" do
    ActsAsTenant.with_tenant(@operator) do
      @member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      bundle = make_bundle(remaining: 5)
      dates = [Date.current + 1, Date.current + 2, Date.current + 5]

      result = Billing::DayPassBundles::ScheduleDays.call(
        user: @member, location: @location, dates: dates, performed_by: @member)

      assert_equal :scheduled, result.outcome
      assert_equal 3, result.day_passes.size
      assert_equal 2, bundle.reload.passes_remaining
      assert_equal dates.sort, @member.day_passes.bundle_sourced.where("day > ?", Date.current).pluck(:day).sort
    end
  end

  test "is all-or-nothing: one bad date rolls back the whole batch" do
    ActsAsTenant.with_tenant(@operator) do
      @member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      bundle = make_bundle(remaining: 5)
      dates = [Date.current + 1, Date.current - 1, Date.current + 3] # middle is invalid

      result = Billing::DayPassBundles::ScheduleDays.call(
        user: @member, location: @location, dates: dates, performed_by: @member)

      assert_equal :invalid_date, result.outcome
      assert_equal Date.current - 1, result.failed_date
      assert_equal 5, bundle.reload.passes_remaining, "nothing should be deducted"
      assert_equal 0, @member.day_passes.bundle_sourced.where("day > ?", Date.current).count
    end
  end
end
