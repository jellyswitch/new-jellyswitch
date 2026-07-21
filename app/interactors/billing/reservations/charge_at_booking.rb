class Billing::Reservations::ChargeAtBooking
  include Interactor

  # Captures a reservation's charge AT BOOKING (ADR 0010), replacing the old
  # authorize-hold-then-settle pipeline. ChargeCalculator is the single source
  # of the amount (Phase 1). Two paths:
  #
  #   * self-serve  → immediate-capture PaymentIntent (mirrors
  #     ChargeExtensionDelta: capture_method "automatic", confirm, off_session).
  #   * net-30 org  → Stripe send_invoice (days_until_due 30). These previously
  #     booked rooms FREE (AuthorizeHold bailed on out_of_band); now invoiced.
  #
  # Idempotent: a no-op if captured_at is already set, plus a Stripe
  # idempotency key (reservation id + amount) so a retried booking never
  # double-charges. captured_at stamps on SUCCESS ONLY — a card decline calls
  # context.fail! and leaves captured_at nil, so SaveRoomReservation#rollback
  # destroys the reservation (no phantom slot). Exempt bookers (member /
  # leaseholder / staff) and demo operators move no money: ChargeCalculator
  # returns 0 for them, so the amount<=0 guard short-circuits.

  delegate :reservation, to: :context

  def call
    return if reservation.captured_at.present? # already billed — idempotent
    return if context.comp # staff comped the booking — no charge

    # Demo operators move no real money on ANY path. The should_charge_* gates in
    # ChargeCalculator already zero most demo bookings, but the metered day-pass /
    # subscription overage branches aren't billing_state-gated — so gate here too
    # (defense in depth) before any Stripe call. (ADR 0010.)
    return unless reservation.room.location.operator.billing_state == "production"

    @amount = Billing::Reservations::ChargeCalculator.call(
      reservation: reservation, minutes: reservation.minutes
    )
    return if @amount <= 0 # free / exempt — no money moves

    if reservation.user.out_of_band?
      charge_via_send_invoice
    else
      charge_via_payment_intent
    end
  end

  private

  attr_reader :amount

  def location
    @location ||= reservation.room.location
  end

  def creds
    @creds ||= { api_key: location.stripe_secret_key, stripe_account: location.stripe_user_id }
  end

  def charge_via_payment_intent
    stripe_customer_id = reservation.user.stripe_customer_id_for_location(location)
    unless stripe_customer_id
      context.fail!(message: 'No Stripe customer on file for this location.')
      return
    end

    pm_id = default_payment_method(stripe_customer_id)
    unless pm_id
      context.fail!(message: 'No payment method on file. Please add a card and try again.')
      return
    end

    intent = Stripe::PaymentIntent.create(
      {
        amount: amount,
        currency: 'usd',
        customer: stripe_customer_id,
        payment_method: pm_id,
        capture_method: 'automatic',
        confirm: true,
        off_session: true,
        description: reservation.charge_description,
        metadata: { reservation_id: reservation.id, kind: 'booking', amount: amount },
      },
      creds.merge(idempotency_key: idempotency_key),
    )

    # Stamp success markers BEFORE the best-effort side effects so captured_at
    # (the idempotency marker) is set the moment the money is taken.
    reservation.update!(
      stripe_payment_intent_id: intent.id,
      authorized_amount_in_cents: amount,
      captured_amount_in_cents: amount,
      paid: true,
      captured_at: Time.current,
    )
    context.payment_intent = intent

    create_local_invoice(
      amount_paid: amount, status: 'paid', stripe_payment_intent_id: intent.id,
    )
    # The admin "paid room" feed card is created by Notifiable::PaidRoomReservation
    # (via SendAdminNotificationForPaidRoom, later in the CreateRoomReservation
    # chain). Do NOT create a second card here — that produced duplicate feed
    # cards for every paid booking.
    send_receipt
    notify_charged
  rescue Stripe::CardError => e
    context.fail!(message: "Card error: #{e.message}")
  rescue Stripe::InvalidRequestError => e
    Honeybadger.notify(e, context: { reservation_id: reservation.id })
    context.fail!(message: 'Could not charge your card for this booking. Please try again.')
  end

  # Net-30 org: send a Stripe invoice (auto_advance finalizes + emails it) and
  # mark the reservation billed. Money isn't captured now, so captured_amount
  # stays 0; the local Invoice (status 'open', amount_due) carries the debt.
  def charge_via_send_invoice
    customer_id = reservation.user.stripe_customer_id_for_location(location)
    unless customer_id
      context.fail!(message: 'No Stripe customer on file for this location.')
      return
    end

    Stripe::InvoiceItem.create(
      { customer: customer_id, currency: 'usd', amount: amount, description: reservation.charge_description },
      creds,
    )
    stripe_invoice = Stripe::Invoice.create(
      { customer: customer_id, auto_advance: true, billing: 'send_invoice', days_until_due: 30 },
      creds.merge(idempotency_key: idempotency_key),
    )

    reservation.update!(
      authorized_amount_in_cents: amount,
      captured_amount_in_cents: 0,
      paid: true,
      captured_at: Time.current,
    )

    create_local_invoice(
      amount_paid: 0, status: 'open', stripe_invoice_id: stripe_invoice.id, due_date: 30.days.from_now,
    )
    # Admin "paid room" feed card is created by Notifiable::PaidRoomReservation, not here.
  rescue Stripe::InvalidRequestError => e
    Honeybadger.notify(e, context: { reservation_id: reservation.id })
    context.fail!(message: 'Could not invoice this booking. Please try again.')
  end

  def idempotency_key
    "resv-#{reservation.id}-charge-#{amount}"
  end

  # Local Invoice mirrors the captured charge so it shows in the member's
  # Invoices screen + admin reports, and so a cancel can refund it (stamped
  # with reservation_id — ADR 0011 refund-all). Best-effort.
  def create_local_invoice(**attrs)
    Invoice.create!(
      {
        billable: reservation.user,
        operator: location.operator,
        location: location,
        reservation: reservation,
        amount_due: amount,
        date: Time.current,
        description: reservation.charge_description,
      }.merge(attrs),
    )
  rescue => e
    Rails.logger.error("ChargeAtBooking invoice failed: #{e.class}: #{e.message}")
    Honeybadger.notify(e, context: { reservation_id: reservation.id })
    nil
  end

  def send_receipt
    UserMailer.meeting_room_charged(reservation.id, amount).deliver_later
  rescue => e
    Rails.logger.error("ChargeAtBooking receipt email failed: #{e.class}: #{e.message}")
    Honeybadger.notify(e, context: { reservation_id: reservation.id })
  end

  # Member-facing charge push (Phase 6), alongside the receipt email. Best-effort
  # and only on the capture path (this method isn't called for net-30 send_invoice,
  # which Stripe receipts itself). Demo/exempt are already excluded upstream.
  def notify_charged
    SendNotificationsJob.perform_later(reservation, "ReservationCharged")
  rescue => e
    Rails.logger.error("ChargeAtBooking charge push failed: #{e.class}: #{e.message}")
    Honeybadger.notify(e, context: { reservation_id: reservation.id })
  end

  def default_payment_method(customer_id)
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
