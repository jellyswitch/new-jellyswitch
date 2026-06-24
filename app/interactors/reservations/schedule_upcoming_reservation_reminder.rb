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

    # Booker "come back — you can get in now" push, fired when door access opens:
    # building_access_window_minutes before start (ADR 0013), read the SAME way the
    # door does so the promise can't drift. Replaces the old fixed 15-min reminder.
    window = building_access_window_minutes(reservation)
    arrival_time = reservation.datetime_in - window.minutes
    if arrival_time > Time.current
      SendReservationReminderJob.set(wait_until: arrival_time).perform_later(reservation.id)
    end

    # Booker "your room is ready" push at start — only when the access window is
    # wide enough that it won't coincide with the arrival push above.
    if window >= SendReservationStartedJob::MIN_WINDOW_MINUTES && reservation.datetime_in > Time.current
      SendReservationStartedJob.set(wait_until: reservation.datetime_in).perform_later(reservation.id)
    end

    # Send a smart "meeting ending" push 10 minutes before the reservation ends
    # Checks if room is free (offer to extend) or booked (wrap up)
    meeting_ending_time = reservation.datetime_out - SendMeetingEndingReminderJob::REMINDER_MINUTES_BEFORE_END.minutes
    if meeting_ending_time > Time.current
      SendMeetingEndingReminderJob.set(wait_until: meeting_ending_time).perform_later(reservation.id)
    end
  end

  private

  # The operator's door-access window in minutes — read exactly as the door
  # (Reservation#access_window_open? / DoorUnlocking) reads it, so the "come back"
  # push and the door open at the same moment.
  def building_access_window_minutes(reservation)
    reservation.room&.location&.operator&.building_access_window_minutes || 60
  end
end
