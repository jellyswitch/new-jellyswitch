class CancelReservation
  include Interactor

  # Unified reservation cancel + refund pipeline (ADR 0011). Member, admin, and
  # web/operator cancels all route here. Under capture-at-booking (ADR 0010) the
  # money is already taken, so a cancel is a REFUND, not a hold release:
  #
  #   - member / web cancel INSIDE the cancellation window → forfeit (no refund;
  #     the charge stands).
  #   - otherwise → refund ALL of the reservation's invoices (booking capture +
  #     any extension deltas), each through Billing::Invoices::Refunds, which
  #     retains the operator's refund_fee_percent. A NotRefundable null-object
  #     (already-refunded / void) is skipped, so the loop never crashes.
  #
  # context.mode: :member (default) | :admin. Admin cancels refund regardless of
  # the window (an operator-forced cancel). Demo operators move no real money.
  def call
    reservation = context.reservation
    mode = context.mode || :member

    # Idempotent fast path: already cancelled → nothing to do, no double refund.
    # Also avoids with_lock's reload tripping over the cancelled: false
    # default_scope on an already-cancelled row.
    return if reservation.cancelled?

    saved = false
    raced = false
    # Lock to serialize concurrent cancels (the capture-vs-cancel race is gone —
    # there's no settle job under capture-at-booking — but a double-cancel still
    # must not double-refund). Reload unscoped to see a cancellation that landed
    # between the guard above and acquiring the lock.
    reservation.with_lock do
      Reservation.unscoped { reservation.reload }
      if reservation.cancelled?
        raced = true
      else
        saved = reservation.update(cancelled: true)
      end
    end

    if !raced && !saved
      context.fail!(message: "Unable to cancel reservation.")
      return
    end

    return if raced
    refund_reservation_invoices(reservation, mode)
    restore_redeemed_bundle_passes(reservation)
  end

  private

  # If this reservation redeemed a bundle pass (ADR 0015) and its coverage day
  # hasn't started yet, give the pass back and drop the minted day pass — the
  # member never had a chance to use the day. Once the coverage day has arrived
  # the pass may have granted access, so it stays spent. Independent of the money
  # refund window (a bundle-covered $0 booking carries no invoice) and of
  # billing_state (a prepaid pass is state-agnostic). Best-effort — never fails
  # the cancel.
  def restore_redeemed_bundle_passes(reservation)
    redemptions = DayPassBundleRedemption.where(reservation_id: reservation.id, kind: "reservation")
    return if redemptions.empty?

    location = reservation.room.location
    tz = ActiveSupport::TimeZone[location.time_zone.presence || "UTC"]
    # The minted pass covers the reservation's CALENDAR day (DayPass.day) — the
    # same basis it was minted on. Only restore while that day is wholly future.
    return if Time.current.in_time_zone(tz).to_date >= reservation.datetime_in.to_date

    redemptions.each do |redemption|
      bundle = redemption.day_pass_bundle
      day_pass = redemption.day_pass
      bundle.with_lock do
        # A single minted pass covers EVERY same-day $0 booking by this user. If
        # another non-cancelled reservation still relies on it, keep the pass
        # spent and the DayPass alive — just re-point the ledger row to a
        # survivor so a later cancel can still restore it. Only the last booking
        # relying on the pass triggers a real refund.
        survivor = other_live_reservation_sharing(reservation, day_pass)
        if survivor
          redemption.update!(reservation_id: survivor.id)
        else
          redemption.destroy
          day_pass&.destroy
          bundle.refund_pass_locked!
        end
      end
    rescue => e
      Rails.logger.error("CancelReservation bundle-pass restore failed for reservation #{reservation.id}: #{e.class}: #{e.message}")
      Honeybadger.notify(e, context: { reservation_id: reservation.id, redemption_id: redemption.id }) rescue nil
    end
  end

  # Another non-cancelled $0-room reservation by the same user, at the minted
  # pass's location, on the pass's calendar day — i.e. one still covered by it.
  def other_live_reservation_sharing(reservation, day_pass)
    return nil unless day_pass
    Reservation.joins(:room)
               .where(user_id: reservation.user_id)
               .where.not(id: reservation.id)
               .where(day_office_pass_id: nil) # office holds never count as coverage survivors (ADR 0026)
               .where(rooms: { location_id: day_pass.location_id })
               .where("rooms.hourly_rate_in_cents = 0 OR rooms.hourly_rate_in_cents IS NULL")
               .where(datetime_in: (day_pass.day - 1).beginning_of_day..(day_pass.day + 1).end_of_day)
               .find { |r| r.datetime_in.to_date == day_pass.day }
  end

  def refund_reservation_invoices(reservation, mode)
    location = reservation.room.location
    operator = location.operator
    return unless operator&.billing_state == "production" # demo: no real refund

    # Member/web inside the window forfeit; admin overrides the window.
    return if mode != :admin && inside_cancellation_window?(reservation, operator)

    invoices_for(reservation).each do |invoice|
      Billing::Invoices::Refunds::Create.call(
        operator: operator,
        invoice: RefundableFactory.for(invoice),
        location: location,
      )
    rescue => e
      Rails.logger.error("CancelReservation refund failed for invoice #{invoice.id}: #{e.class}: #{e.message}")
      Honeybadger.notify(e, context: { reservation_id: reservation.id, invoice_id: invoice.id })
    end
  end

  # All invoices belonging to the reservation. Prefer the reservation_id link
  # (Phase 2); fall back to the PaymentIntent id so pre-Phase-2 reservations
  # (captured via the retired CaptureHold, no reservation_id) still refund.
  def invoices_for(reservation)
    invoices = reservation.invoices.to_a
    if reservation.stripe_payment_intent_id.present?
      invoices += Invoice.where(stripe_payment_intent_id: reservation.stripe_payment_intent_id).to_a
    end
    invoices.uniq
  end

  def inside_cancellation_window?(reservation, operator)
    window_hours = operator&.try(:cancellation_window_hours).to_i
    window_hours > 0 && (reservation.datetime_in - Time.current) < window_hours.hours
  end
end
