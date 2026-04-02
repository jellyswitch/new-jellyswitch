class Billing::Reservations::UpdateBillingAndCreateRoomReservation
  include Interactor::Organizer

  organize(
    Billing::Payment::UpdateUserPayment,
    Billing::Reservations::SaveRoomReservation,
    Billing::Reservations::SaveStripeInvoice,
    Billing::Reservations::ChargeReservationInvoice,
    Billing::Reservations::GrantFreeDayPass,
    CreateNotificationsAsync,
    SendAdminNotificationForPaidRoom,
    Billing::Reservations::ScheduleReservationEmails
  )
end
