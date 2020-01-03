class Billing::Reservations::CreateRoomReservation
  include Interactor::Organizer
  
  organize(
    Billing::Reservations::SaveRoomReservation,
    Billing::Reservations::SaveStripeInvoice,
    CreateNotifications
  )
end