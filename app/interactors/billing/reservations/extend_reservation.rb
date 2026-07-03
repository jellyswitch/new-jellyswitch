class Billing::Reservations::ExtendReservation
  include Interactor

  # Capture-at-booking (ADR 0010): the original charge is already captured at
  # booking, so every extension is just a delta charge — ChargeExtensionDelta
  # places a separate auto-capture PaymentIntent for the additional minutes only
  # (a no-op when the new total isn't higher, e.g. an exempt member). There is
  # no pre-start hold to re-authorize anymore.
  def call
    Billing::Reservations::UpdateReservationDuration.call(context)
    return if context.failure?

    Billing::Reservations::ChargeCredits.call(context)
    return if context.failure?

    Billing::Reservations::ChargeExtensionDelta.call(context)
  end
end
