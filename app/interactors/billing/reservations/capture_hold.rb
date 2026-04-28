# Captures a reservation's authorization hold for the booked amount.
# Called from SettleReservationJob at datetime_in. Slot is committed
# by then (cancel cutoff at datetime_in - 1 minute), so capturing for
# the full booked minutes is correct — including for no-shows.
#
# Idempotent — if already captured (or we're racing with cancel), bails.
# Wraps the decision in with_lock to close that race cleanly.
class Billing::Reservations::CaptureHold
  include Interactor

  delegate :reservation, :actual_minutes, to: :context

  def call
    return if reservation.stripe_payment_intent_id.blank?
    return if reservation.captured_at.present?
    return if reservation.cancelled?

    location = reservation.room.location
    creds = { api_key: location.stripe_secret_key, stripe_account: location.stripe_user_id }

    minutes = actual_minutes || reservation.minutes
    actual_charge_cents = Billing::Reservations::ChargeCalculator.call(
      reservation: reservation, minutes: minutes
    )

    authorized = reservation.authorized_amount_in_cents.to_i
    capture_cents = [actual_charge_cents, authorized].min

    captured_now = false
    reservation.with_lock do
      # Re-check after lock acquisition — a concurrent cancel may have
      # voided the PI between the early-return checks above and now.
      # Reservation has default_scope cancelled: false, so reload it
      # unscoped to actually see a cancellation that just landed.
      Reservation.unscoped { reservation.reload }
      return if reservation.captured_at.present?
      return if reservation.cancelled?

      if capture_cents <= 0
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
      captured_now = true
    end

    return unless captured_now

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

    # Send a receipt email so the member has a record of the charge.
    # Background-deliver so email-provider hiccups don't fail the job.
    begin
      UserMailer.meeting_room_charged(reservation.id, capture_cents).deliver_later
    rescue => e
      Rails.logger.error("CaptureHold receipt email failed: #{e.class}: #{e.message}")
      Honeybadger.notify(e, context: { reservation_id: reservation.id })
    end
  rescue Stripe::InvalidRequestError => e
    Rails.logger.warn("CaptureHold error on reservation #{reservation.id}: #{e.message}")
    Honeybadger.notify(e, context: { reservation_id: reservation.id })
    # Don't re-raise — we don't want end_now/settle to fail for the user.
    reservation.update!(captured_at: Time.current)
  end

end
