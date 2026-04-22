# Schedules SettleReservationJob to run at reservation's natural end
# time to auto-capture the authorized hold if the user didn't end
# early. Idempotent on the CaptureHold side.
class Reservations::ScheduleSettleReservation
  include Interactor

  def call
    reservation = context.reservation
    return unless reservation&.stripe_payment_intent_id.present?
    settle_at = reservation.datetime_out
    return if settle_at.past?

    SettleReservationJob.set(wait_until: settle_at).perform_later(reservation.id)
  rescue => e
    Rails.logger.error("ScheduleSettleReservation failed: #{e.class}: #{e.message}")
    Honeybadger.notify(e)
  end
end
