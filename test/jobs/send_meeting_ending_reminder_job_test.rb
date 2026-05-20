require "test_helper"

class SendMeetingEndingReminderJobTest < ActiveJob::TestCase
  def setup
    @reservation = reservations(:room_reservation)
    # Push the reservation forward so datetime_out is comfortably in the
    # future for the default-case assertions.
    @reservation.update!(datetime_in: 1.hour.from_now, minutes: 60)
    @reservation.update_column(:cancelled, false)
  end

  test "sends pushes when reservation is active and not over" do
    SendMeetingEndingReminderJob.any_instance.expects(:send_ios).once
    SendMeetingEndingReminderJob.any_instance.expects(:send_android).once

    SendMeetingEndingReminderJob.perform_now(@reservation.id)
  end

  test "skips when reservation is nil" do
    SendMeetingEndingReminderJob.any_instance.expects(:send_ios).never
    SendMeetingEndingReminderJob.any_instance.expects(:send_android).never

    SendMeetingEndingReminderJob.perform_now(0) # nonexistent id
  end

  test "skips when reservation is cancelled" do
    @reservation.update_column(:cancelled, true)

    SendMeetingEndingReminderJob.any_instance.expects(:send_ios).never
    SendMeetingEndingReminderJob.any_instance.expects(:send_android).never

    SendMeetingEndingReminderJob.perform_now(@reservation.id)
  end

  test "skips when reservation was ended early (end_now)" do
    # Simulate `Reservation#end_now!` — sets ended_early without
    # touching `cancelled`. The previously scheduled job should not
    # fire the original-end-time push.
    @reservation.update!(ended_early: true, minutes: 5)

    SendMeetingEndingReminderJob.any_instance.expects(:send_ios).never
    SendMeetingEndingReminderJob.any_instance.expects(:send_android).never

    SendMeetingEndingReminderJob.perform_now(@reservation.id)
  end

  test "skips when reservation's end time has already passed" do
    # Past-due defensive guard — covers extensions that re-scheduled,
    # manual datetime edits, or any path that leaves datetime_out behind.
    @reservation.update!(datetime_in: 2.hours.ago, minutes: 30)

    SendMeetingEndingReminderJob.any_instance.expects(:send_ios).never
    SendMeetingEndingReminderJob.any_instance.expects(:send_android).never

    SendMeetingEndingReminderJob.perform_now(@reservation.id)
  end
end
