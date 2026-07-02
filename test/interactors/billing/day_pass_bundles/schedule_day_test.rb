require "test_helper"

class Billing::DayPassBundles::ScheduleDayTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

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

  # C2: in-lock idempotency guard
  test "scheduling the same future date twice returns :already_covered the second time with only one pass burned" do
    ActsAsTenant.with_tenant(@operator) do
      @member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      bundle = make_bundle(remaining: 5)
      date = Date.current + 3

      first  = Billing::DayPassBundles::ScheduleDay.call(
        user: @member, location: @location, date: date, performed_by: @member)
      second = Billing::DayPassBundles::ScheduleDay.call(
        user: @member, location: @location, date: date, performed_by: @member)

      assert_equal :scheduled,       first.outcome
      assert_equal :already_covered, second.outcome
      assert_equal 4, bundle.reload.passes_remaining, "only one pass burned for the same date"
    end
  end

  # C1: defer follow_up review email for future-date schedules
  test "scheduling a FUTURE date does NOT enqueue the follow_up email" do
    ActsAsTenant.with_tenant(@operator) do
      @member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      make_bundle(remaining: 5)

      assert_no_enqueued_jobs only: SendProductEmailJob do
        Billing::DayPassBundles::ScheduleDay.call(
          user: @member, location: @location, date: Date.current + 2, performed_by: @member)
      end
    end
  end

  test "scheduling for today (same-day) DOES enqueue the follow_up email" do
    ActsAsTenant.with_tenant(@operator) do
      @member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      make_bundle(remaining: 5)

      assert_enqueued_with(job: SendProductEmailJob) do
        Billing::DayPassBundles::ScheduleDay.call(
          user: @member, location: @location, date: Date.current, performed_by: @member)
      end
    end
  end

  # m2: unparseable date
  test "an unparseable date string returns :invalid_date and mints nothing" do
    ActsAsTenant.with_tenant(@operator) do
      @member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      make_bundle(remaining: 5)

      result = Billing::DayPassBundles::ScheduleDay.call(
        user: @member, location: @location, date: "not-a-date", performed_by: @member)

      assert_equal :invalid_date, result.outcome
      assert_equal 0, @member.day_passes.count
    end
  end

  # m5: expiry-boundary — soonest-expiring bundle is skipped when it would be expired by the target date
  test "expiry-boundary: burns perpetual bundle for a date beyond the expiring bundle's window" do
    ActsAsTenant.with_tenant(@operator) do
      @member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      expiring  = make_bundle(remaining: 5, expires_at: 10.days.from_now)
      perpetual = make_bundle(remaining: 5, expires_at: nil)

      # 5 days out — expiring bundle still valid
      result5 = Billing::DayPassBundles::ScheduleDay.call(
        user: @member, location: @location, date: Date.current + 5, performed_by: @member)
      assert_equal :scheduled, result5.outcome
      assert_equal 4, expiring.reload.passes_remaining,  "expiring bundle used for near date"
      assert_equal 5, perpetual.reload.passes_remaining

      # 15 days out — expiring bundle would be expired; must use perpetual
      result15 = Billing::DayPassBundles::ScheduleDay.call(
        user: @member, location: @location, date: Date.current + 15, performed_by: @member)
      assert_equal :scheduled, result15.outcome
      assert_equal 4, expiring.reload.passes_remaining,  "expiring bundle not touched for far date"
      assert_equal 4, perpetual.reload.passes_remaining, "perpetual bundle used for far date"
    end
  end
end
