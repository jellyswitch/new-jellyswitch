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

    # Create a local Invoice record so the captured charge shows up in
    # the member's Invoices screen and admin reports, and so refunds
    # can be issued against it.
    invoice_record = nil
    begin
      invoice_record = Invoice.create!(
        billable: reservation.user,
        operator: location.operator,
        location: location,
        amount_due: capture_cents,
        amount_paid: capture_cents,
        status: 'paid',
        date: Time.current,
        stripe_payment_intent_id: reservation.stripe_payment_intent_id,
        description: reservation.charge_description,
      )
    rescue => e
      Rails.logger.error("CaptureHold invoice creation failed: #{e.class}: #{e.message}")
      Honeybadger.notify(e, context: { reservation_id: reservation.id })
    end

    # Post a feed item so the admin sees the actual charge in the
    # management feed (the booking-time feed only fires for up-front
    # paid rooms; day-pass overages happen here at capture time).
    begin
      FeedItem.create!(
        operator: location.operator,
        location: location,
        user: reservation.user,
        blob: {
          'type' => 'paid-room-reservation',
          'user_name' => reservation.user.name,
          'reservation_id' => reservation.id,
          'invoice_id' => invoice_record&.id,
          'charge_amount_in_cents' => capture_cents,
          'room_name' => reservation.room.name,
          'minutes' => reservation.minutes,
        },
      )
    rescue => e
      Rails.logger.error("CaptureHold feed item failed: #{e.class}: #{e.message}")
      Honeybadger.notify(e, context: { reservation_id: reservation.id })
    end
  rescue Stripe::InvalidRequestError => e
    Rails.logger.warn("CaptureHold error on reservation #{reservation.id}: #{e.message}")
    Honeybadger.notify(e, context: { reservation_id: reservation.id })
    # Don't re-raise — we don't want end_now/settle to fail for the user.
    reservation.update!(captured_at: Time.current)
  end

  private

  # Compute what this reservation should actually cost based on the
  # minutes the user really used. Unlike the pricing endpoint, the
  # "already used" total must EXCLUDE this reservation itself (we're
  # settling it right now — counting it against itself would double
  # up the overage).
  def compute_actual_charge(actual_minutes)
    user = reservation.user
    room = reservation.room
    location = room.location
    date = reservation.datetime_in.to_date

    # Priced rooms = straight hourly rate × minutes.
    if room.hourly_rate_in_cents.to_i > 0
      return ((room.hourly_rate_in_cents * actual_minutes) / 60.0).round
    end

    # Day pass overage
    day_pass = user.day_passes.where(day: date).first
    if day_pass && day_pass.day_pass_type&.has_meeting_room_limit?
      return day_pass_overage_cents(actual_minutes, day_pass)
    end

    # Subscription overage
    sub = user.active_subscription_for_location(location)
    if sub && sub.plan&.has_meeting_room_limit?
      return subscription_overage_cents(actual_minutes, sub)
    end

    0
  end

  def day_pass_overage_cents(actual_minutes, day_pass)
    allotment = day_pass.day_pass_type.included_meeting_room_minutes.to_i
    other_used = Reservation.joins(:room).where(user_id: reservation.user_id, cancelled: false)
                            .where(datetime_in: reservation.datetime_in.to_date.beginning_of_day..reservation.datetime_in.to_date.end_of_day)
                            .where('rooms.hourly_rate_in_cents = 0 OR rooms.hourly_rate_in_cents IS NULL')
                            .where.not(id: reservation.id)
                            .sum(:minutes)
    free_remaining = [allotment - other_used, 0].max
    over = [actual_minutes - free_remaining, 0].max
    return 0 if over <= 0
    over_rounded = (over / 15.0).ceil * 15
    rate_per_min = day_pass.day_pass_type.overage_rate_in_cents.to_f / 60.0
    (rate_per_min * over_rounded).round
  end

  def subscription_overage_cents(actual_minutes, sub)
    allotment = sub.plan.included_meeting_room_minutes.to_i
    period_start, period_end = sub.current_billing_period
    return 0 unless period_start
    other_used = Reservation.where(user_id: reservation.user_id, cancelled: false)
                            .where(datetime_in: period_start..period_end)
                            .where.not(id: reservation.id)
                            .sum(:minutes)
    free_remaining = [allotment - other_used, 0].max
    over = [actual_minutes - free_remaining, 0].max
    return 0 if over <= 0
    over_rounded = (over / 15.0).ceil * 15
    rate_per_min = sub.plan.overage_rate_in_cents.to_f / 60.0
    (rate_per_min * over_rounded).round
  end
end
