class Billing::Reservations::UpdateBillingAndCreateRoomReservation
  include Interactor::Organizer

  # New-card-on-booking flow: attach the card to the customer, then
  # use the same PaymentIntent hold pipeline as CreateRoomReservation
  # so all paid bookings settle at end-of-reservation.
  organize(
    Billing::Payment::UpdateUserPayment,
    Billing::Reservations::SaveRoomReservation,
    Billing::Reservations::AuthorizeHold,
    Billing::Reservations::GrantFreeDayPass,
    Reservations::ScheduleSettleReservation,
    CreateNotificationsAsync,
    SendAdminNotificationForPaidRoom,
    Billing::Reservations::ScheduleReservationEmails
  )
end
