class Reservations::ScheduleUpcomingReservationReminder
  include Interactor

  def call
    reservation = context.reservation
    reminder_time = reservation.datetime_in - Reservation::REMINDER_OFFSET_MINUTES

    if reminder_time > Time.current
      SendUpcomingReservationReminderJob.set(wait_until: reminder_time).perform_later(reservation.id)
    else
      SendUpcomingReservationReminderJob.perform_now(reservation.id)
    end
  end
end
