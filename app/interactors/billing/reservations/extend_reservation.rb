class Billing::Reservations::ExtendReservation
  include Interactor

  # Extensions branch on whether the original capture has fired:
  #
  # * Pre-start (captured_at blank) — original hold is still pending.
  #   AuthorizeHold cancels the prior PaymentIntent and re-authorizes
  #   a hold for the new total max charge. The already-scheduled
  #   SettleReservationJob fires at datetime_in and captures the new
  #   total then; no reschedule needed (extension doesn't move
  #   datetime_in).
  #
  # * Post-start (captured_at present) — original capture is done and
  #   can't be "raised." ChargeExtensionDelta places a separate
  #   auto-capture PaymentIntent for the cost of the additional
  #   minutes only.
  def call
    Billing::Reservations::UpdateReservationDuration.call(context)
    return if context.failure?

    Billing::Reservations::ChargeCredits.call(context)
    return if context.failure?

    # context.is_extend is already true (set by UpdateReservationDuration).
    if context.reservation.captured_at.present?
      Billing::Reservations::ChargeExtensionDelta.call(context)
    else
      Billing::Reservations::AuthorizeHold.call(context)
    end
  end
end
