require "test_helper"

class Billing::DayPassBundles::ScheduleDaysTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @location.update!(working_day_start: "08:00", working_day_end: "18:00")
  end

  def day_office_push_types
    enqueued_jobs.select { |j| j[:job] == SendNotificationsJob }
                 .map { |j| j[:args].last }
                 .grep(/DayOffice/)
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

  # --- Task 11: Day Office notifications fire AFTER the batch commits ------
  #
  # ScheduleDays holds ONE transaction across every date. Enqueuing from inside
  # ScheduleDay would hand Sidekiq a job naming rows that may never commit —
  # the worker can dequeue before COMMIT (job silently discarded, mailer
  # nil-bails, member never hears) or after a ROLLBACK (a confirmation for an
  # office nobody has). So ScheduleDay stashes and ScheduleDays fires.

  test "a happy office batch announces each day exactly once" do
    ActsAsTenant.with_tenant(@operator) do
      @member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      make_office_bundle(member: @member)

      result = Billing::DayPassBundles::ScheduleDays.call(
        user: @member, location: @location, dates: [Date.current + 1, Date.current + 2],
        performed_by: @member, enforce_daily_limit: true)

      assert_equal :scheduled, result.outcome
      assert_equal %w[DayOfficeAssigned DayOfficeAssigned], day_office_push_types
      assert_equal 2, enqueued_jobs.count { |j|
        j[:job].to_s.include?("MailDeliveryJob") && j[:args][1] == "day_office_confirmation"
      }
    end
  end

  test "a rolled-back office batch announces NOTHING" do
    ActsAsTenant.with_tenant(@operator) do
      @member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      _bundle, room_a, room_b = make_office_bundle(member: @member)
      ok_date   = Date.current + 1
      full_date = Date.current + 2
      fill_office_pool!(full_date, room_a, room_b)

      result = Billing::DayPassBundles::ScheduleDays.call(
        user: @member, location: @location, dates: [ok_date, full_date],
        performed_by: @member, enforce_daily_limit: true)

      assert_equal :sold_out, result.outcome
      # The first date DID allocate and stash a notification before the second
      # blew the batch up — proving the enqueue is gated on the commit, not on
      # ScheduleDay's own success.
      assert_empty day_office_push_types
      assert_equal 0, enqueued_jobs.count { |j|
        j[:job].to_s.include?("MailDeliveryJob") && j[:args][1] == "day_office_confirmation"
      }
      assert_empty @member.day_passes.where(day: ok_date)
    end
  end

  # Direct proof of ordering: record the open-transaction depth at the moment
  # Notify is called. Inside ScheduleDays' transaction it would be one deeper
  # than at the call site (the suite's own wrapping transaction is the shared
  # baseline), so equality means the enqueue happened after the block closed.
  test "the notification is composed outside ScheduleDays' transaction" do
    ActsAsTenant.with_tenant(@operator) do
      @member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      make_office_bundle(member: @member)
      baseline = ActiveRecord::Base.connection.open_transactions
      observed = []

      DayOffices::Notify.stub(:assigned, ->(day_pass:) {
        observed << ActiveRecord::Base.connection.open_transactions
      }) do
        Billing::DayPassBundles::ScheduleDays.call(
          user: @member, location: @location, dates: [Date.current + 1, Date.current + 2],
          performed_by: @member, enforce_daily_limit: true)
      end

      assert_equal [baseline, baseline], observed,
                   "notifications must be composed at the caller's transaction depth, not inside the batch's"
    end
  end

  test "staff batch scheduling stays silent" do
    ActsAsTenant.with_tenant(@operator) do
      @member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      make_office_bundle(member: @member)

      result = Billing::DayPassBundles::ScheduleDays.call(
        user: @member, location: @location, dates: [Date.current + 1, Date.current + 2],
        performed_by: @member) # no enforce_daily_limit → staff path

      assert_equal :scheduled, result.outcome
      assert_empty day_office_push_types
    end
  end

  test "a standard batch schedules with no Day Office notifications" do
    ActsAsTenant.with_tenant(@operator) do
      @member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      make_bundle(remaining: 5)

      result = Billing::DayPassBundles::ScheduleDays.call(
        user: @member, location: @location, dates: [Date.current + 1, Date.current + 2],
        performed_by: @member, enforce_daily_limit: true)

      assert_equal :scheduled, result.outcome
      assert_empty day_office_push_types
    end
  end
end
