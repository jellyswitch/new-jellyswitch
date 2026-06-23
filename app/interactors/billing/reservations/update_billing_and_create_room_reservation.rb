class Billing::Reservations::UpdateBillingAndCreateRoomReservation
  include Interactor::Organizer

  # New-card-on-booking flow: attach the card to the customer, then
  # use the same PaymentIntent hold pipeline as CreateRoomReservation
  # so all paid bookings settle at end-of-reservation.
  # GrantFreeDayPass removed (ADR 0012) — paid bookings mint no comp pass.
  # See CreateRoomReservation for the full rationale (the "Brad bug").
  organize(
    Billing::Payment::UpdateUserPayment,
    Billing::Reservations::SaveRoomReservation,
    Billing::Reservations::AuthorizeHold,
    Reservations::ScheduleSettleReservation,
    CreateNotificationsAsync,
    SendAdminNotificationForPaidRoom,
    Billing::Reservations::ScheduleReservationEmails
  )
end
