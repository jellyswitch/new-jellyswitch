require "test_helper"

class SendReservationReminderJobTest < ActiveSupport::TestCase
  setup do
    @room = rooms(:small_meeting_room)
    @room.reservations.delete_all
    @user = users(:cowork_tahoe_member)
  end

  test "sends when the reservation is imminent" do
    res = Reservation.create!(user: @user, room: @room, datetime_in: 10.minutes.from_now, minutes: 60)
    SendNotificationsJob.expects(:perform_now).with(res, "ReservationReminder").once
    SendReservationReminderJob.perform_now(res.id)
  end

  test "skips a reservation rescheduled out of the reminder window" do
    res = Reservation.create!(user: @user, room: @room, datetime_in: 3.hours.from_now, minutes: 60)
    SendNotificationsJob.expects(:perform_now).never
    SendReservationReminderJob.perform_now(res.id)
  end

  test "skips a reservation that has already started" do
    res = Reservation.create!(user: @user, room: @room, datetime_in: 5.minutes.ago, minutes: 60)
    SendNotificationsJob.expects(:perform_now).never
    SendReservationReminderJob.perform_now(res.id)
  end

  test "skips a cancelled reservation" do
    res = Reservation.create!(user: @user, room: @room, datetime_in: 10.minutes.from_now, minutes: 60)
    res.update_column(:cancelled, true)
    SendNotificationsJob.expects(:perform_now).never
    SendReservationReminderJob.perform_now(res.id)
  end

  # Phase 6: fires once door access opens — building_access_window_minutes before
  # start (ADR 0013), not a fixed 15 min.
  test "fires once the access window has opened" do
    @room.location.operator.update!(building_access_window_minutes: 60)
    res = Reservation.create!(user: @user, room: @room, datetime_in: 50.minutes.from_now, minutes: 60)
    # Access opened 10 min ago (50 − 60), still before start → fire.
    SendNotificationsJob.expects(:perform_now).with(res, "ReservationReminder").once
    SendReservationReminderJob.perform_now(res.id)
  end

  test "does not fire before the access window opens" do
    @room.location.operator.update!(building_access_window_minutes: 30)
    res = Reservation.create!(user: @user, room: @room, datetime_in: 50.minutes.from_now, minutes: 60)
    # Window opens at start − 30 = 20 min from now → not yet.
    SendNotificationsJob.expects(:perform_now).never
    SendReservationReminderJob.perform_now(res.id)
  end

  # Phase 6 review fix #1: a duplicate job (an edit re-enqueues without cancelling
  # the old one) must not double-send — the idempotency marker dedups.
  test "fires only once even when the job runs twice" do
    @room.location.operator.update!(building_access_window_minutes: 60)
    res = Reservation.create!(user: @user, room: @room, datetime_in: 50.minutes.from_now, minutes: 60)
    SendNotificationsJob.expects(:perform_now).with(res, "ReservationReminder").once
    SendReservationReminderJob.perform_now(res.id)
    SendReservationReminderJob.perform_now(res.id) # second copy no-ops via the marker
    assert_not_nil res.reload.arrival_notified_at
  end
end
