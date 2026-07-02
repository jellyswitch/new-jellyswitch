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
    SendUpcomingReservationReminderJob.unstub :set
    SendReservationReminderJob.unstub :set
    SendReservationStartedJob.unstub :set
  end

  test "schedules reminder job 10 minutes before future reservation time" do
    reminder_time = @future_reservation.datetime_in - Reservation::REMINDER_OFFSET_MINUTES

    job_mock = Minitest::Mock.new

    SendUpcomingReservationReminderJob.expects(:set).with(wait_until: reminder_time).returns(job_mock)

    job_mock.expect(:perform_later, nil, [@future_reservation.id])

    result = Reservations::ScheduleUpcomingReservationReminder.call(reservation: @future_reservation)

    assert result.success?
    job_mock.verify
  end

  test "perform job immediately for a upcoming reservation" do
    SendUpcomingReservationReminderJob.expects(:perform_now).with(@upcoming_reservation.id)

    result = Reservations::ScheduleUpcomingReservationReminder.call(reservation: @upcoming_reservation)

    assert result.success?
  end

  test "perform job immediately for a past reservation" do
    SendUpcomingReservationReminderJob.expects(:perform_now).with(@past_reservation.id)

    result = Reservations::ScheduleUpcomingReservationReminder.call(reservation: @past_reservation)

    assert result.success?
  end

  # Phase 6: the booker "come back" push fires when door access opens —
  # building_access_window_minutes before start (ADR 0013), NOT a fixed 15 min.
  test "schedules the booker arrival push building_access_window_minutes before start" do
    @room.location.operator.update!(building_access_window_minutes: 60)
    arrival = @future_reservation.datetime_in - 60.minutes
    job_mock = Minitest::Mock.new
    SendReservationReminderJob.expects(:set).with(wait_until: arrival).returns(job_mock)
    job_mock.expect(:perform_later, nil, [@future_reservation.id])

    Reservations::ScheduleUpcomingReservationReminder.call(reservation: @future_reservation)

    job_mock.verify
  end

  test "schedules the started push at start when the access window is wide enough" do
    @room.location.operator.update!(building_access_window_minutes: 60)
    job_mock = Minitest::Mock.new
    SendReservationStartedJob.expects(:set).with(wait_until: @future_reservation.datetime_in).returns(job_mock)
    job_mock.expect(:perform_later, nil, [@future_reservation.id])

    Reservations::ScheduleUpcomingReservationReminder.call(reservation: @future_reservation)

    job_mock.verify
  end

  test "does NOT schedule the started push when the access window is narrow" do
    @room.location.operator.update!(building_access_window_minutes: 10)
    SendReservationStartedJob.expects(:set).never

    Reservations::ScheduleUpcomingReservationReminder.call(reservation: @future_reservation)
  end

  # Phase 6 review fix #3: a short-lead booking whose access window already opened
  # gets the arrival push immediately (perform_now), not dropped.
  test "fires the arrival push immediately for a short-lead booking inside the window" do
    @room.location.operator.update!(building_access_window_minutes: 60)
    short = Reservation.new(room: @room, user: @user, datetime_in: 20.minutes.from_now, minutes: 60)
    SendReservationReminderJob.expects(:perform_now).with(short.id)

    Reservations::ScheduleUpcomingReservationReminder.call(reservation: short)
  end

  # Phase 6 review fix #2: a scheduling/enqueue error must NOT propagate (it runs
  # after ChargeAtBooking captured money; a raise would roll back the booking).
  test "swallows a scheduling error instead of failing the booking" do
    SendUpcomingReservationReminderJob.stubs(:set).raises(StandardError.new("redis down"))

    result = Reservations::ScheduleUpcomingReservationReminder.call(reservation: @future_reservation)

    assert result.success?
  end
end
