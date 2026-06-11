class AuthorizeReservationHoldJob < ApplicationJob
  queue_as :default

  # Deferred AuthorizeHold for far-future reservations.
  # AuthorizeHoldOrSchedule queues this for datetime_in - 6 days so the
  # hold lands inside Stripe's ~7-day manual-capture window. If the
  # reservation has been cancelled or already authorized in the meantime
  # (e.g. extension flow placed a fresh hold), bail. On failure mark
  # the reservation payment_failed so the member and operator see it.
  def perform(reservation_id)
    reservation = Reservation.find_by(id: reservation_id)
    return if reservation.nil?
    return if reservation.cancelled?
    return if reservation.captured_at.present?
    return if reservation.stripe_payment_intent_id.present?

    location = reservation.room.location
    user = reservation.user

    day_pass_charge_info = user.day_pass_reservation_charge_info(
      location, reservation.datetime_in.to_date, reservation.minutes,
      room: reservation.room,
    ) rescue nil
    subscription_charge_info = user.subscription_reservation_charge_info(
      location, reservation.minutes, room: reservation.room, at: reservation.datetime_in,
    ) rescue nil

    result = Billing::Reservations::AuthorizeHold.call(
      reservation: reservation,
      user: user,
      location: location,
      day_pass_charge_info: day_pass_charge_info,
      subscription_charge_info: subscription_charge_info,
    )

    if result.success?
      # Capture-job scheduling at booking time was skipped for deferred
      # holds (no PI yet). Now that the hold is in place, queue the
      # capture for datetime_in. ScheduleSettleReservation is no-op-safe
      # if the job is already queued.
      Reservations::ScheduleSettleReservation.call(reservation: reservation.reload)
    else
      Reservations::MarkPaymentFailed.call(
        reservation: reservation,
        reason: result.message || 'Authorization failed',
      )
    end
  rescue => e
    Honeybadger.notify(e, context: { reservation_id: reservation_id })
    Rails.logger.error("AuthorizeReservationHoldJob failed: #{e.class}: #{e.message}")
    Reservations::MarkPaymentFailed.call(reservation: Reservation.find_by(id: reservation_id), reason: e.message) rescue nil
  end
end
