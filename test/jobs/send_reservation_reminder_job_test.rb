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
end
