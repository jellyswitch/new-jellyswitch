class SettleReservationJob < ApplicationJob
  queue_as :default

  def perform(reservation_id)
    reservation = Reservation.find_by(id: reservation_id)
    return if reservation.nil?
    return if reservation.cancelled?
    return if reservation.captured_at.present? # already settled (end_now fired)
    return if reservation.stripe_payment_intent_id.blank?

    Billing::Reservations::CaptureHold.call(
      reservation: reservation,
      actual_minutes: reservation.minutes,
    )
  rescue => e
    Honeybadger.notify(e, context: { reservation_id: reservation_id })
    Rails.logger.error("SettleReservationJob failed: #{e.class}: #{e.message}")
  end
end
