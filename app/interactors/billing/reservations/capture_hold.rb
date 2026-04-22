# Captures the actual charge on a reservation's authorization hold,
# based on the minutes the user really used. Releases the rest of
# the hold (i.e. Stripe only captures the amount you tell it; the
# difference between authorized_amount and captured_amount is
# returned to the card automatically by Stripe).
#
# Called from:
#   - Reservation#end_now! path (user taps "End now")
#   - Scheduled SettleReservationJob at datetime_out
#
# Idempotent — if already captured, does nothing.
class Billing::Reservations::CaptureHold
  include Interactor

  delegate :reservation, :actual_minutes, to: :context

  def call
    return if reservation.stripe_payment_intent_id.blank?
    return if reservation.captured_at.present?

    location = reservation.room.location
    creds = { api_key: location.stripe_secret_key, stripe_account: location.stripe_user_id }

    minutes = actual_minutes || reservation.minutes
    actual_charge_cents = compute_actual_charge(minutes)

    authorized = reservation.authorized_amount_in_cents.to_i
    capture_cents = [actual_charge_cents, authorized].min

    if capture_cents <= 0
      # Nothing owed — cancel the hold entirely.
      Stripe::PaymentIntent.cancel(reservation.stripe_payment_intent_id, {}, creds) rescue nil
      reservation.update!(captured_amount_in_cents: 0, captured_at: Time.current)
      return
    end

    intent = Stripe::PaymentIntent.capture(
      reservation.stripe_payment_intent_id,
      { amount_to_capture: capture_cents },
      creds,
    )
    reservation.update!(captured_amount_in_cents: capture_cents, captured_at: Time.current)
    context.payment_intent = intent
  rescue Stripe::InvalidRequestError => e
    Rails.logger.warn("CaptureHold error on reservation #{reservation.id}: #{e.message}")
    Honeybadger.notify(e, context: { reservation_id: reservation.id })
    # Don't re-raise — we don't want end_now/settle to fail for the user.
    reservation.update!(captured_at: Time.current)
  end

  private

  # Mirrors the pricing logic used at booking-time, applied to the
  # minutes the user actually sat in the room.
  def compute_actual_charge(actual_minutes)
    user = reservation.user
    room = reservation.room
    location = room.location
    date = reservation.datetime_in.to_date

    # Priced rooms = straight hourly rate × minutes.
    if room.hourly_rate_in_cents.to_i > 0
      return ((room.hourly_rate_in_cents * actual_minutes) / 60.0).round
    end

    # Free rooms: run the same charge_info methods with actual_minutes.
    sub_info = user.subscription_reservation_charge_info(location, actual_minutes, room: room) rescue nil
    dp_info = user.day_pass_reservation_charge_info(location, date, actual_minutes, room: room) rescue nil

    if sub_info
      return sub_info[:overage_amount_in_cents].to_i
    elsif dp_info
      return dp_info[:overage_amount_in_cents].to_i
    else
      return 0
    end
  end
end
