require "test_helper"

class Reservations::ScheduleUpcomingReservationReminderTest < ActiveSupport::TestCase
  def setup
    @user = users(:cowork_tahoe_member)
    @room = rooms(:small_meeting_room)

    @future_time = Time.current + 1.day
    @upcoming_time = Time.current + 5.minutes
    @past_time = Time.current - 1.hour

    @future_reservation = Reservation.new(
      room: @room,
      user: @user,
      datetime_in: @future_time,
      minutes: 60,
    )

    @upcoming_reservation = Reservation.new(
      room: @room,
      user: @user,
      datetime_in: @upcoming_time,
      minutes: 60,
    )

    @past_reservation = Reservation.new(
      room: @room,
      user: @user,
      datetime_in: @upcoming_time,
      minutes: 60,
    )

    @remind_job_mock = Minitest::Mock.new
  end

  def teardown
    RemindUpcomingReservationJob.unstub :set
  end

  test "schedules reminder job 10 minutes before future reservation time" do
    reminder_time = @future_reservation.datetime_in - 10.minutes

    job_mock = Minitest::Mock.new

    RemindUpcomingReservationJob.expects(:set).with(wait_until: reminder_time).returns(job_mock)

    job_mock.expect(:perform_later, nil, [@future_reservation.id])

    result = Reservations::ScheduleUpcomingReservationReminder.call(reservation: @future_reservation)

    assert result.success?
    job_mock.verify
  end

  test "perform job immediately for a upcoming reservation" do
    RemindUpcomingReservationJob.expects(:perform_now).with(@upcoming_reservation.id)

    result = Reservations::ScheduleUpcomingReservationReminder.call(reservation: @upcoming_reservation)

    assert result.success?
  end

  test "perform job immediately for a past reservation" do
    RemindUpcomingReservationJob.expects(:perform_now).with(@past_reservation.id)

    result = Reservations::ScheduleUpcomingReservationReminder.call(reservation: @past_reservation)

    assert result.success?
  end
end
