class Billing::Reservations::UpdateBillingAndCreateRoomReservation
  include Interactor::Organizer

  # New-card-on-booking flow: attach the card to the customer, then
  # CAPTURE AT BOOKING via ChargeAtBooking (ADR 0010), the same path as
  # CreateRoomReservation. GrantFreeDayPass removed (ADR 0012) — paid bookings
  # mint no comp pass. See CreateRoomReservation for the full rationale.
  organize(
    Billing::Payment::UpdateUserPayment,
    Billing::Reservations::SaveRoomReservation,
    Billing::Reservations::RedeemBundlePass,
    Billing::Reservations::ChargeAtBooking,
    CreateNotificationsAsync,
    SendAdminNotificationForPaidRoom,
    Billing::Reservations::ScheduleReservationEmails
  )
end
