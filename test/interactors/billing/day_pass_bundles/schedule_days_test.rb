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

  # m2: unparseable string in batch rolls back as :invalid_date
  test "a bad date string in the batch rolls back the whole batch as :invalid_date" do
    ActsAsTenant.with_tenant(@operator) do
      @member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      bundle = make_bundle(remaining: 5)
      dates = [(Date.current + 1).iso8601, "not-a-date", (Date.current + 3).iso8601]

      result = Billing::DayPassBundles::ScheduleDays.call(
        user: @member, location: @location, dates: dates, performed_by: @member)

      assert_equal :invalid_date, result.outcome
      assert_equal 5, bundle.reload.passes_remaining, "nothing burned when batch has bad date"
      assert_equal 0, @member.day_passes.bundle_sourced.where("day > ?", Date.current).count
    end
  end

  test "a sold-out date mid-batch rolls back the whole batch and reports the type" do
    ActsAsTenant.with_tenant(@operator) do
      @member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      bundle = make_bundle(remaining: 5)
      bundle.day_pass_type.update!(daily_limit: 1)
      ok_date   = Date.current + 1
      full_date = Date.current + 2
      other = create(:user, operator: @operator, original_location: @location, current_location: @location)
      DayPass.create!(user: other, billable: other, operator: @operator, location: @location,
                      day_pass_type: bundle.day_pass_type, day: full_date, imported: true)

      result = Billing::DayPassBundles::ScheduleDays.call(
        user: @member, location: @location, dates: [ok_date.iso8601, full_date.iso8601],
        performed_by: @member, enforce_daily_limit: true)

      assert_equal :sold_out, result.outcome
      assert_equal full_date, result.failed_date
      assert_equal bundle.day_pass_type, result.day_pass_type
      assert_equal 5, bundle.reload.passes_remaining, "the ok-date burn must roll back too"
      assert_empty @member.day_passes.where(day: ok_date), "no pass may survive the rollback"
    end
  end
end
