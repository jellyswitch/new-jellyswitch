class Reservations::ScheduleUpcomingReservationReminder
  include Interactor

  def call
    reservation = context.reservation
    reminder_time = reservation.datetime_in - 10.minutes

    if reminder_time > Time.current
      RemindUpcomingReservationJob.set(wait_until: reminder_time).perform_later(reservation.id)
    else
      RemindUpcomingReservationJob.perform_now(reservation.id)
    end
  end
end
