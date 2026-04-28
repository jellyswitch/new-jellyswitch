class SettleReservationJob < ApplicationJob
  queue_as :default

  def perform(reservation_id)
    reservation = Reservation.find_by(id: reservation_id)
    return if reservation.nil?
    return if reservation.cancelled?
    return if reservation.captured_at.present? # already settled (end_now fired)
    return if reservation.stripe_payment_intent_id.blank?
    # If the reservation was extended after this job was scheduled, the
    # new datetime_out is in the future and a fresh job is queued for
    # that time. Skip — let the later job do the capture.
    return if reservation.datetime_out > Time.current + 1.minute

    Billing::Reservations::CaptureHold.call(
      reservation: reservation,
      actual_minutes: reservation.minutes,
    )
  rescue => e
    Honeybadger.notify(e, context: { reservation_id: reservation_id })
    Rails.logger.error("SettleReservationJob failed: #{e.class}: #{e.message}")
  end
end
