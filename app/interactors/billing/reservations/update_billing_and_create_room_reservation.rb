class Billing::Reservations::UpdateBillingAndCreateRoomReservation
  include Interactor::Organizer

  organize(
    Billing::Payment::UpdateUserPayment,
    Billing::Reservations::CreateRoomReservation,
    Billing::Reservations::SaveStripeInvoice
  )
end