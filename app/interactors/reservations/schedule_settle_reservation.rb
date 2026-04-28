# Schedules SettleReservationJob to run at reservation's start time
# (datetime_in). Once start passes, the slot is committed — by then
# cancellation is disallowed (see ReservationsController#destroy
# 1-minute cutoff), so capturing the hold is the right operation.
# Idempotent on the CaptureHold side (it bails when captured_at is
# already set — used by extensions that re-schedule).
#
# Reserve Now bookings (datetime_in ~= now) end up with the job firing
# almost immediately; that's intentional — uniform code path beats a
# Reserve-Now special case.
class Reservations::ScheduleSettleReservation
  include Interactor

  def call
    reservation = context.reservation
    return unless reservation&.stripe_payment_intent_id.present?
    settle_at = reservation.datetime_in
    SettleReservationJob.set(wait_until: [settle_at, Time.current].max).perform_later(reservation.id)
  rescue => e
    Rails.logger.error("ScheduleSettleReservation failed: #{e.class}: #{e.message}")
    Honeybadger.notify(e)
  end
end
