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

    # Send a smart "meeting ending" push 10 minutes before the reservation ends
    # Checks if room is free (offer to extend) or booked (wrap up)
    meeting_ending_time = reservation.datetime_out - SendMeetingEndingReminderJob::REMINDER_MINUTES_BEFORE_END.minutes
    if meeting_ending_time > Time.current
      SendMeetingEndingReminderJob.set(wait_until: meeting_ending_time).perform_later(reservation.id)
    end
  end
end
