class Reservations::ScheduleUpcomingReservationReminder
  include Interactor

  def call
    reservation = context.reservation
    reminder_time = reservation.datetime_in - Reservation::REMINDER_OFFSET_MINUTES

    # Notify the current occupant that someone else has booked after them
    if reminder_time > Time.current
      SendUpcomingReservationReminderJob.set(wait_until: reminder_time).perform_later(reservation.id)
    else
      SendUpcomingReservationReminderJob.perform_now(reservation.id)
    end

    # Send a push notification to the booker 15 minutes before their reservation starts
    booker_reminder_time = reservation.datetime_in - 15.minutes
    if booker_reminder_time > Time.current
      SendReservationReminderJob.set(wait_until: booker_reminder_time).perform_later(reservation.id)
    end
  end
end
