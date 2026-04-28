class SettleReservationJob < ApplicationJob
  queue_as :default

  # Captures the authorized hold at the reservation's start
  # (datetime_in). Members commit to a slot once start passes — the
  # 1-minute cancel cutoff before datetime_in (see
  # Api::V1::ReservationsController#destroy) makes a window where the
  # member can no longer back out. Capturing then is the right move
  # for both regular usage and no-shows. Extensions made after start
  # go through Billing::Reservations::ChargeExtensionDelta and don't
  # round-trip through this job again.
  def perform(reservation_id)
    reservation = Reservation.find_by(id: reservation_id)
    return if reservation.nil?
    return if reservation.cancelled?
    return if reservation.captured_at.present?
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
