require "test_helper"

# DayOffices::Notify is the single composer for Day Office notifications
# (ADR 0026). Two properties matter more than the copy: it only ever ENQUEUES
# (so a caller can fire it right after a lock without blocking a door), and it
# never raises (so a broken push can't fail a burn, a purchase, or an unlock).
class DayOffices::NotifyTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper

  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @location.update!(time_zone: "Pacific Time (US & Canada)",
                      working_day_start: "08:00", working_day_end: "18:00")
    @day = Date.current + 5
  end

  # Day Office push types in enqueue order. Filtered because creating the
  # fixture member fires an unrelated signup PointOfContactAlert.
  def day_office_push_types
    enqueued_jobs.select { |j| j[:job] == SendNotificationsJob }
                 .map { |j| j[:args].last }
                 .grep(/DayOffice/)
  end

  # Returns [day_pass, hold].
  def assigned_pass(day: @day)
    ActsAsTenant.with_tenant(@operator) do
      member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      bundle, = make_office_bundle(member: member)
      pass = DayPass.create!(user: member, billable: member, operator: @operator, location: @location,
                             day_pass_type: bundle.day_pass_type, day: day, imported: true)
      [pass, DayOffices::Allocator.allocate!(day_pass: pass)]
    end
  end

  # --- assigned ----------------------------------------------------------

  test "assigned enqueues the member push and the confirmation email" do
    pass, = assigned_pass

    assert_enqueued_with(job: SendNotificationsJob, args: [pass, "DayOfficeAssigned"]) do
      assert_enqueued_email_with UserMailer, :day_office_confirmation, args: [pass.id] do
        DayOffices::Notify.assigned(day_pass: pass)
      end
    end
  end

  test "assigned is a no-op for a nil pass" do
    assert_no_enqueued_jobs do
      DayOffices::Notify.assigned(day_pass: nil)
    end
  end

  # --- walk_in_no_office -------------------------------------------------

  test "walk_in_no_office pushes the member AND the admins, and sends no email" do
    pass, = assigned_pass

    assert_enqueued_with(job: SendNotificationsJob, args: [pass, "DayOfficeUnavailable"]) do
      assert_enqueued_with(job: SendNotificationsJob, args: [pass, "DayOfficeUnassignedAlert"]) do
        DayOffices::Notify.walk_in_no_office(day_pass: pass)
      end
    end
    # Nothing to confirm — there is no office. A confirmation email here would
    # be actively wrong.
    assert_no_enqueued_emails do
      DayOffices::Notify.walk_in_no_office(day_pass: pass)
    end
  end

  # Ordering is the failure-mode guarantee: a raise between the two enqueues
  # must leave staff paged and the member silent, never the reverse ("see
  # staff" delivered to someone whose staff were never told).
  test "the admin alert is enqueued before the member push" do
    pass, = assigned_pass

    DayOffices::Notify.walk_in_no_office(day_pass: pass)

    assert_equal %w[DayOfficeUnassignedAlert DayOfficeUnavailable], day_office_push_types
  end

  test "booked_no_office uses the booking-variant admin alert, admin first" do
    pass, = assigned_pass

    assert_no_enqueued_emails do
      DayOffices::Notify.booked_no_office(day_pass: pass)
    end

    assert_equal %w[DayOfficeUnassignedBookingAlert DayOfficeUnavailable], day_office_push_types
  end

  test "neither no-office variant fires for a nil pass" do
    assert_no_enqueued_jobs do
      DayOffices::Notify.walk_in_no_office(day_pass: nil)
      DayOffices::Notify.booked_no_office(day_pass: nil)
    end
  end

  # --- reassigned (Task 12 consumes this) --------------------------------

  test "reassigned enqueues the member push and the reassignment email with the old room name" do
    _pass, hold = assigned_pass

    assert_enqueued_with(job: SendNotificationsJob, args: [hold, "DayOfficeReassigned"]) do
      assert_enqueued_email_with UserMailer, :day_office_reassigned, args: [hold.id, "Office B"] do
        DayOffices::Notify.reassigned(hold: hold, old_room_name: "Office B")
      end
    end
  end

  test "reassigned is a no-op for a nil hold" do
    assert_no_enqueued_jobs do
      DayOffices::Notify.reassigned(hold: nil, old_room_name: "Office B")
    end
  end

  # --- best-effort -------------------------------------------------------

  test "a failure inside notification composition never reaches the caller" do
    pass, hold = assigned_pass
    UserMailer.stubs(:day_office_confirmation).raises(RuntimeError, "mailer exploded")
    UserMailer.stubs(:day_office_reassigned).raises(RuntimeError, "mailer exploded")
    SendNotificationsJob.stubs(:perform_later).raises(RuntimeError, "queue down")

    assert_nothing_raised do
      DayOffices::Notify.assigned(day_pass: pass)
      DayOffices::Notify.walk_in_no_office(day_pass: pass)
      DayOffices::Notify.booked_no_office(day_pass: pass)
      DayOffices::Notify.reassigned(hold: hold, old_room_name: "Office B")
    end
  end

  # Swallowing must not mean going quiet: `report` rescues Honeybadger itself,
  # so without this a broken reporter would hide every notification failure
  # behind two layers of rescue and nobody would ever find out.
  test "swallowed failures are still reported to Honeybadger with the pass id" do
    pass, = assigned_pass
    SendNotificationsJob.stubs(:perform_later).raises(RuntimeError, "queue down")
    reported = []
    Honeybadger.stubs(:notify).with { |error, opts| reported << [error, opts]; true }

    DayOffices::Notify.walk_in_no_office(day_pass: pass)

    assert_equal 1, reported.size, "the rescue must report, not just log"
    error, opts = reported.first
    assert_equal "queue down", error.message
    assert_equal pass.id, opts[:context][:day_pass_id]
  end
end
