class Billing::Reservations::UpdateBillingAndCreateRoomReservation
  include Interactor::Organizer

  organize(
    Billing::Payment::UpdateUserPayment,
    CreateRoomReservation
  )
end