require "test_helper"

class SendReservationStartedJobTest < ActiveSupport::TestCase
  setup do
    @room = rooms(:small_meeting_room)
    @room.reservations.delete_all
    @user = users(:cowork_tahoe_member)
  end

  test "sends when the reservation has just started" do
    res = Reservation.create!(user: @user, room: @room, datetime_in: 1.minute.ago, minutes: 60)
    SendNotificationsJob.expects(:perform_now).with(res, "ReservationStarted").once
    SendReservationStartedJob.perform_now(res.id)
  end

  test "skips a reservation not due yet (stale early fire after a reschedule)" do
    res = Reservation.create!(user: @user, room: @room, datetime_in: 2.hours.from_now, minutes: 60)
    SendNotificationsJob.expects(:perform_now).never
    SendReservationStartedJob.perform_now(res.id)
  end

  test "skips a reservation that has already ended" do
    res = Reservation.create!(user: @user, room: @room, datetime_in: 3.hours.ago, minutes: 60)
    SendNotificationsJob.expects(:perform_now).never
    SendReservationStartedJob.perform_now(res.id)
  end

  test "skips a cancelled reservation" do
    res = Reservation.create!(user: @user, room: @room, datetime_in: 1.minute.ago, minutes: 60)
    res.update_column(:cancelled, true)
    SendNotificationsJob.expects(:perform_now).never
    SendReservationStartedJob.perform_now(res.id)
  end
end
