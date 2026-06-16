class SendReservationReminderJob < ApplicationJob
  queue_as :default

  # The booker "starts in ~15 minutes" push. A reservation edited to a LATER
  # start leaves a stale copy of this job queued at the old time; only fire
  # when the reservation is still upcoming AND genuinely imminent.
  REMINDER_WINDOW = 20.minutes

  def perform(reservation_id)
    reservation = Reservation.find_by(id: reservation_id)
    return if reservation.nil? || reservation.cancelled?

    # `datetime_in` is the reservation's start instant; only fire when it's
    # still in the future (not already started/past) AND within the reminder
    # window. A booking rescheduled to a later start falls outside the window
    # so its stale job is skipped; one moved earlier/into the past is skipped
    # as already-started.
    start = reservation.datetime_in
    return unless start > Time.current && start <= Time.current + REMINDER_WINDOW

    SendNotificationsJob.perform_now(reservation, "ReservationReminder")
  rescue => e
    Honeybadger.notify(e)
    Rails.logger.error("SendReservationReminderJob failed: #{e.class}: #{e.message}")
  end
end
