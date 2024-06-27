require "test_helper"

class RemindUpcomingReservationJobTest < ActiveJob::TestCase
  def setup
    @user = users(:cowork_tahoe_member)
    @another_user = users(:cowork_tahoe_admin)

    @room = rooms(:small_meeting_room)
    @upcoming_time = Time.current + 15.minutes

    @upcoming_reservation = Reservation.create!(
      room: @room,
      user: @user,
      datetime_in: @upcoming_time,
      minutes: 60,
    )
  end

  test "performs reminder for upcoming reservation" do
    prior_reservation = Reservation.create!(
      room: @room,
      user: @another_user,
      datetime_in: @upcoming_time - 1.hour,
      minutes: 60,
    )

    SendNotificationsJob.expects(:perform_now).with(prior_reservation, "UpcomingReservationReminder")

    RemindUpcomingReservationJob.perform_now(@upcoming_reservation.id)
  end

  test "does not send reminder when no prior reservation exists" do
    SendNotificationsJob.expects(:perform_now).never

    RemindUpcomingReservationJob.perform_now(@upcoming_reservation.id)
  end

  test "does not send reminder when the upcoming reservation is cancelled" do
    @upcoming_reservation.update!(cancelled: true)

    SendNotificationsJob.expects(:perform_now).never

    RemindUpcomingReservationJob.perform_now(@upcoming_reservation.id)
  end

  test "does not send reminder when the reservation is not found" do
    not_existed_id = -1

    SendNotificationsJob.expects(:perform_now).never

    RemindUpcomingReservationJob.perform_now(not_existed_id)
  end
end
