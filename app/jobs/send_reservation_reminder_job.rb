class SendReservationReminderJob < ApplicationJob
  queue_as :default

  def perform(reservation_id)
    reservation = Reservation.find_by(id: reservation_id)
    return if reservation.nil? || reservation.cancelled?

    SendNotificationsJob.perform_now(reservation, "ReservationReminder")
  rescue => e
    Honeybadger.notify(e)
    Rails.logger.error("SendReservationReminderJob failed: #{e.class}: #{e.message}")
  end
end
