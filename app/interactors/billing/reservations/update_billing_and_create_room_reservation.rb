class Billing::Reservations::UpdateBillingAndCreateRoomReservation
  include Interactor::Organizer

  organize(
    Billing::Payment::UpdateUserPayment,
    Billing::Reservations::SaveRoomReservation,
    Billing::Reservations::SaveStripeInvoice,
    Billing::Reservations::GrantFreeDayPass,
    CreateNotificationsAsync,
    SendAdminNotificationForPaidRoom
  )
end
