require "test_helper"

class Billing::DayPassBundles::CancelScheduledDayTest < ActiveSupport::TestCase
  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
  end

  def schedule(date)
    Billing::DayPassBundles::ScheduleDay.call(
      user: @member, location: @location, date: date, performed_by: @member).day_pass
  end

  def make_bundle(remaining: 5)
    dpt = DayPassType.create!(operator: @operator, location: @location, name: "Pack",
                              amount_in_cents: 20000, quantity: 5, available: true, visible: true)
    DayPassBundle.create!(user: @member, operator: @operator, location: @location, day_pass_type: dpt,
                          quantity_purchased: 5, passes_remaining: remaining, purchased_at: Time.current)
  end

  test "cancelling a future scheduled day restores the pass and removes the dated pass" do
    ActsAsTenant.with_tenant(@operator) do
      @member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      bundle = make_bundle(remaining: 5)
      day_pass = schedule(Date.current + 4)
      assert_equal 4, bundle.reload.passes_remaining

      result = Billing::DayPassBundles::CancelScheduledDay.call(day_pass: day_pass, performed_by: @member)

      assert_equal :cancelled, result.outcome
      assert_equal 5, bundle.reload.passes_remaining
      assert_nil DayPass.find_by(id: day_pass.id), "the future pass is removed"
      assert_equal 1, bundle.redemptions.where(kind: "schedule_cancel").count
      assert_equal (Date.current + 4).iso8601, bundle.redemptions.where(kind: "schedule_cancel").first.guest_name
    end
  end

  test "cannot cancel once the day has started (today or past)" do
    ActsAsTenant.with_tenant(@operator) do
      @member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      bundle = make_bundle(remaining: 5)
      # Build a today-dated bundle pass directly (a started day)
      day_pass = DayPass.create!(user: @member, billable: @member, operator: @operator, location: @location,
                                 day_pass_type: bundle.day_pass_type, day: Date.current, imported: true)
      bundle.burn!(kind: :entry, performed_by: @member, day_pass: day_pass)
      assert_equal 4, bundle.reload.passes_remaining

      result = Billing::DayPassBundles::CancelScheduledDay.call(day_pass: day_pass, performed_by: @member)

      assert_equal :too_late, result.outcome
      assert_equal 4, bundle.reload.passes_remaining
      assert DayPass.find_by(id: day_pass.id), "pass is untouched"
    end
  end

  test "rejects a pass that isn't a bundle-sourced scheduled pass" do
    ActsAsTenant.with_tenant(@operator) do
      @member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      dpt = DayPassType.create!(operator: @operator, location: @location, name: "Single",
                                amount_in_cents: 4000, quantity: 1, available: true, visible: true)
      plain = create(:day_pass, user: @member, billable: @member, operator: @operator, location: @location,
                     day_pass_type: dpt, day: Date.current + 2)

      result = Billing::DayPassBundles::CancelScheduledDay.call(day_pass: plain, performed_by: @member)
      assert_equal :not_scheduled, result.outcome
    end
  end
end
