require "test_helper"

# The walk-in burn (ADR 0026, decision #4). Someone with a Day Office bundle
# taps a door without having scheduled anything. The pass burns and the door
# opens EITHER WAY — a full pool costs them the office, never the entry.
class Billing::DayPassBundles::ConsumeOnEntryDayOfficeTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper

  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    # 08:00–18:00 is exactly the 600-minute span DayOfficeHelper#fill_office_pool!
    # books, so "full pool" really means full.
    @location.update!(time_zone: "Pacific Time (US & Canada)",
                      working_day_start: "08:00", working_day_end: "18:00")
    @zone = ActiveSupport::TimeZone["Pacific Time (US & Canada)"]
    @today = Date.current
    ActsAsTenant.with_tenant(@operator) do
      @member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      @bundle, @room_a, @room_b = make_office_bundle(member: @member)
    end
  end

  def day_office_push_types
    enqueued_jobs.select { |j| j[:job] == SendNotificationsJob }
                 .map { |j| j[:args].last }
                 .grep(/DayOffice/)
  end

  def enter!
    travel_to @zone.parse("#{@today} 10:30") do
      Billing::DayPassBundles::ConsumeOnEntry.call(user: @member, location: @location)
    end
  end

  # --- office free -------------------------------------------------------

  test "a walk-in with a free pool burns, mints, and takes an office" do
    result = nil
    assert_enqueued_with(job: SendNotificationsJob, args: ->(a) { a[1] == "DayOfficeAssigned" }) do
      result = enter!
    end

    assert_equal :redeemed, result.outcome
    assert_equal 4, @bundle.reload.passes_remaining

    pass = @member.day_passes.for_location(@location).for_day(@today).sole
    hold = pass.reload_office_hold
    assert_equal @room_a, hold.room
    # The hold is linked ONLY through reservations.day_office_pass_id (ADR 0019);
    # the pass's own `reservation` means "the member's covered booking" and there
    # isn't one here.
    assert_nil pass.reservation_id
    assert_equal pass.id, hold.day_office_pass_id
  end

  test "an assigned walk-in sends the confirmation email and no walk-in alert" do
    assert_enqueued_email_with UserMailer, :day_office_confirmation, args: ->(a) { a.first.present? } do
      enter!
    end

    assert_equal %w[DayOfficeAssigned], day_office_push_types
  end

  # --- pool full: still burns, still enters ------------------------------

  test "a walk-in with a full pool STILL burns and enters, with no office" do
    ActsAsTenant.with_tenant(@operator) { fill_office_pool!(@today, @room_a, @room_b) }

    result = enter!

    assert_equal :redeemed, result.outcome, "a full pool must never cost someone their entry"
    assert_equal 4, @bundle.reload.passes_remaining, "the pass is still spent — it bought access"
    pass = @member.day_passes.for_location(@location).for_day(@today).sole
    assert_nil pass.reload_office_hold
    assert_nil result.office_hold
  end

  test "a full-pool walk-in notifies the member AND staff, and sends no confirmation" do
    ActsAsTenant.with_tenant(@operator) { fill_office_pool!(@today, @room_a, @room_b) }

    assert_no_enqueued_emails do
      enter!
    end

    # Walk-in variant ("arrived"), admin paged before the member is told.
    assert_equal %w[DayOfficeUnassignedAlert DayOfficeUnavailable], day_office_push_types
    pass = @member.day_passes.for_location(@location).for_day(@today).sole
    assert_equal "No offices are left today — your pass still works; see staff.",
                 NotifiableFactory.for(pass, "DayOfficeUnavailable").send(:message)
    assert_includes NotifiableFactory.for(pass, "DayOfficeUnassignedAlert").send(:message),
                    "arrived on a Day Office pass"
  end

  # --- idempotency: one entry, one notification --------------------------

  test "a second tap the same day neither burns nor notifies again" do
    enter!
    assert_equal 4, @bundle.reload.passes_remaining

    result = nil
    assert_no_enqueued_jobs(only: SendNotificationsJob) do
      result = enter!
    end

    assert_equal :already_covered, result.outcome
    assert_equal 4, @bundle.reload.passes_remaining
  end

  # --- standard bundles are untouched ------------------------------------

  test "a standard bundle burns exactly as before, with no office and no office notifications" do
    ActsAsTenant.with_tenant(@operator) do
      other = create(:user, operator: @operator, original_location: @location, current_location: @location)
      type = create(:day_pass_type, operator: @operator, location: @location)
      bundle = create(:day_pass_bundle, user: other, billable: other, operator: @operator,
                      location: @location, day_pass_type: type)

      result = nil
      assert_no_difference "Reservation.count" do
        travel_to @zone.parse("#{@today} 10:30") do
          result = Billing::DayPassBundles::ConsumeOnEntry.call(user: other, location: @location)
        end
      end

      assert_equal :redeemed, result.outcome
      assert_equal 4, bundle.reload.passes_remaining
      assert_nil result.office_hold
      assert_empty day_office_push_types
    end
  end
end
