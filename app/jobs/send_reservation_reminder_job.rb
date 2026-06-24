class SendReservationReminderJob < ApplicationJob
  queue_as :default

  # The booker "come back — your door access is open" push (ADR 0013). Fires
  # when access opens: building_access_window_minutes before start. A reservation
  # edited to a different start leaves a stale copy of this job queued at the old
  # time; the window-aware guard makes it self-skip.
  GRACE = 2.minutes

  def perform(reservation_id)
    reservation = Reservation.find_by(id: reservation_id)
    return if reservation.nil? || reservation.cancelled?

    start = reservation.datetime_in
    window = (reservation.room&.location&.operator&.building_access_window_minutes || 60).minutes
    arrival_at = start - window
    # Fire only when we're at/after the intended access-open moment and still
    # before start. A booking moved LATER → arrival_at is later → skip; one moved
    # earlier or already started → now >= start → skip.
    return unless Time.current >= arrival_at - GRACE && Time.current < start

    SendNotificationsJob.perform_now(reservation, "ReservationReminder")
  rescue => e
    Honeybadger.notify(e)
    Rails.logger.error("SendReservationReminderJob failed: #{e.class}: #{e.message}")
  end
end
