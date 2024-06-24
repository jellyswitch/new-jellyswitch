class Billing::Reservations::ExtendReservation
  include Interactor::Organizer

  organize(
    Billing::Reservations::UpdateReservationDuration,
    Billing::Reservations::ChargeCredits,
    Billing::Reservations::SaveStripeInvoice,
  )
end
