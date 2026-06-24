class SendReservationStartedJob < ApplicationJob
  queue_as :default

  # The booker "your room is ready / booking has started" push, fired at
  # datetime_in. Only scheduled when the access window is at least this wide, so
  # it doesn't coincide with the arrival ("come back") push (ADR 0013 / Phase 6).
  MIN_WINDOW_MINUTES = 15
  GRACE = 2.minutes

  def perform(reservation_id)
    reservation = Reservation.find_by(id: reservation_id)
    return if reservation.nil? || reservation.cancelled?

    start = reservation.datetime_in
    # Fire around start; a moved booking's stale job self-skips (now far from
    # start, or the reservation has already ended).
    return unless Time.current >= start - GRACE && Time.current < reservation.datetime_out

    # Claim the started marker atomically (see SendReservationReminderJob) so a
    # duplicate job from an edit can't double-send.
    return if Reservation.where(id: reservation.id, started_notified_at: nil)
                         .update_all(started_notified_at: Time.current).zero?

    SendNotificationsJob.perform_now(reservation, "ReservationStarted")
  rescue => e
    Honeybadger.notify(e)
    Rails.logger.error("SendReservationStartedJob failed: #{e.class}: #{e.message}")
  end
end
