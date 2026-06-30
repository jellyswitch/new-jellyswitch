require "test_helper"

class Billing::DayPassBundles::ScheduleDayTest < ActiveSupport::TestCase
  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
  end

  def make_bundle(qty: 5, remaining: 5, expires_at: nil, created_at: Time.current)
    dpt = DayPassType.create!(operator: @operator, location: @location, name: "#{qty}-Pack",
                              amount_in_cents: 20000, quantity: qty, available: true, visible: true)
    DayPassBundle.create!(user: @member, operator: @operator, location: @location, day_pass_type: dpt,
                          quantity_purchased: qty, passes_remaining: remaining, expires_at: expires_at,
                          created_at: created_at, purchased_at: Time.current)
  end

  test "scheduling a future day mints a dated bundle-sourced pass and decrements the bundle" do
    ActsAsTenant.with_tenant(@operator) do
      @member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      bundle = make_bundle(remaining: 5)
      date = Date.current + 3

      result = Billing::DayPassBundles::ScheduleDay.call(
        user: @member, location: @location, date: date, performed_by: @member)

      assert_equal :scheduled, result.outcome
      assert_equal date, result.day_pass.day
      assert_equal @location, result.day_pass.location
      assert result.day_pass.imported, "scheduled pass must be imported (no lifecycle side effects)"
      assert_equal 4, bundle.reload.passes_remaining
      assert_equal 1, bundle.redemptions.where(kind: "entry").count
      assert_equal result.day_pass.id, bundle.redemptions.where(kind: "entry").first.day_pass_id
    end
  end

  test "draws from the soonest-expiring bundle first" do
    ActsAsTenant.with_tenant(@operator) do
      @member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      perpetual = make_bundle(remaining: 5, expires_at: nil)
      expiring   = make_bundle(remaining: 5, expires_at: 20.days.from_now)

      Billing::DayPassBundles::ScheduleDay.call(
        user: @member, location: @location, date: Date.current + 2, performed_by: @member)

      assert_equal 4, expiring.reload.passes_remaining, "should burn the soonest-expiring bundle"
      assert_equal 5, perpetual.reload.passes_remaining
    end
  end

  test "rejects a date already covered by an existing pass (no wasted pass)" do
    ActsAsTenant.with_tenant(@operator) do
      @member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      bundle = make_bundle(remaining: 5)
      date = Date.current + 4
      create(:day_pass, user: @member, billable: @member, operator: @operator, location: @location,
             day_pass_type: bundle.day_pass_type, day: date)

      result = Billing::DayPassBundles::ScheduleDay.call(
        user: @member, location: @location, date: date, performed_by: @member)

      assert_equal :already_covered, result.outcome
      assert_equal 5, bundle.reload.passes_remaining
    end
  end

  test "rejects a past date and a date beyond the horizon" do
    ActsAsTenant.with_tenant(@operator) do
      @member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      make_bundle(remaining: 5)

      past = Billing::DayPassBundles::ScheduleDay.call(
        user: @member, location: @location, date: Date.current - 1, performed_by: @member)
      assert_equal :invalid_date, past.outcome

      far = Billing::DayPassBundles::ScheduleDay.call(
        user: @member, location: @location,
        date: Date.current + Billing::DayPassBundles::ScheduleDay::HORIZON_DAYS + 1, performed_by: @member)
      assert_equal :invalid_date, far.outcome
    end
  end

  test "rejects when no passes remain" do
    ActsAsTenant.with_tenant(@operator) do
      @member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      make_bundle(remaining: 0)
      result = Billing::DayPassBundles::ScheduleDay.call(
        user: @member, location: @location, date: Date.current + 1, performed_by: @member)
      assert_equal :no_bundle, result.outcome
    end
  end
end
