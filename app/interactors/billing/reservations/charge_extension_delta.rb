class Billing::Reservations::ChargeExtensionDelta
  include Interactor

  # Charges the additional cost of an extension when the original
  # reservation has already been captured. We can't "raise" a captured
  # PaymentIntent — and we don't want to mess with refunds for the
  # common case — so we place a separate auto-capture PaymentIntent
  # for just the delta and roll the totals into the reservation's
  # authorized_amount/captured_amount aggregates.
  #
  # Used only by ExtendReservation when reservation.captured_at is set.

  delegate :reservation, to: :context

  def call
    return if reservation.user.out_of_band?

    location = reservation.room.location
    creds = { api_key: location.stripe_secret_key, stripe_account: location.stripe_user_id }

    new_total = Billing::Reservations::ChargeCalculator.call(
      reservation: reservation, minutes: reservation.minutes
    )
    delta = new_total - reservation.captured_amount_in_cents.to_i
    return if delta <= 0

    stripe_customer_id = reservation.user.stripe_customer_id_for_location(location)
    unless stripe_customer_id
      context.fail!(message: 'No Stripe customer on file for this location.')
      return
    end

    pm_id = default_payment_method(stripe_customer_id, location, creds)
    unless pm_id
      context.fail!(message: 'No payment method on file. Please add a card and try again.')
      return
    end

    description = "#{location.operator.name} meeting room extension - #{reservation.pretty_datetime}"

    intent = Stripe::PaymentIntent.create(
      {
        amount: delta,
        currency: 'usd',
        customer: stripe_customer_id,
        payment_method: pm_id,
        capture_method: 'automatic',
        confirm: true,
        off_session: true,
        description: description,
        metadata: {
          reservation_id: reservation.id,
          kind: 'extension_delta',
          delta_amount: delta,
        },
      },
      # Idempotency key keyed on the resulting total: a double-tapped "extend"
      # (both requests computing the same delta before either bumps
      # captured_amount) reuses the same key, so Stripe places ONE PaymentIntent
      # instead of double-charging. A genuinely separate later extension yields a
      # different new_total → different key → charges normally. (ChargeAtBooking
      # already keys its capture the same way.)
      creds.merge(idempotency_key: "resv-#{reservation.id}-ext-#{new_total}"),
    )

    reservation.update!(
      authorized_amount_in_cents: reservation.authorized_amount_in_cents.to_i + delta,
      captured_amount_in_cents: reservation.captured_amount_in_cents.to_i + delta,
    )
    context.payment_intent = intent

    invoice_record = nil
    begin
      invoice_record = Invoice.create!(
        billable: reservation.user,
        operator: location.operator,
        location: location,
        reservation: reservation, # so a cancel refunds extension deltas too (ADR 0011)
        amount_due: delta,
        amount_paid: delta,
        status: 'paid',
        date: Time.current,
        stripe_payment_intent_id: intent.id,
        description: description,
      )
    rescue => e
      Rails.logger.error("ChargeExtensionDelta invoice failed: #{e.class}: #{e.message}")
      Honeybadger.notify(e, context: { reservation_id: reservation.id })
    end

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
          'charge_amount_in_cents' => delta,
          'room_name' => reservation.room.name,
          'minutes' => reservation.minutes,
          'extension' => true,
        },
      )
    rescue => e
      Rails.logger.error("ChargeExtensionDelta feed item failed: #{e.class}: #{e.message}")
      Honeybadger.notify(e, context: { reservation_id: reservation.id })
    end

    begin
      UserMailer.meeting_room_charged(reservation.id, delta, kind: 'extension').deliver_later
    rescue => e
      Rails.logger.error("ChargeExtensionDelta receipt email failed: #{e.class}: #{e.message}")
      Honeybadger.notify(e, context: { reservation_id: reservation.id })
    end
  rescue Stripe::CardError => e
    context.fail!(message: "Card error: #{e.message}")
  rescue Stripe::InvalidRequestError => e
    Honeybadger.notify(e, context: { reservation_id: reservation.id })
    context.fail!(message: 'Could not charge for the extension. Please try again.')
  end

  private

  def default_payment_method(customer_id, _location, creds)
    customer = Stripe::Customer.retrieve(customer_id, creds)
    ds = customer.try(:default_source)
    return ds if ds.is_a?(String) && ds.present?
    pm_id = customer.try(:invoice_settings)&.try(:default_payment_method)
    return pm_id if pm_id.is_a?(String) && pm_id.present?
    pms = Stripe::PaymentMethod.list({ customer: customer_id, type: 'card', limit: 1 }, creds)
    pms.data.first&.id
  rescue => e
    Rails.logger.error("default_payment_method lookup failed: #{e.class}: #{e.message}")
    nil
  end
end
