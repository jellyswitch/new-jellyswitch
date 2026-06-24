class Billing::Reservations::UpdateBillingAndCreateRoomReservation
  include Interactor::Organizer

  # New-card-on-booking flow: attach the card to the customer, then
  # CAPTURE AT BOOKING via ChargeAtBooking (ADR 0010), the same path as
  # CreateRoomReservation. GrantFreeDayPass removed (ADR 0012) — paid bookings
  # mint no comp pass. See CreateRoomReservation for the full rationale.
  # ScheduleUpcomingReservationReminder added in Phase 6 so new-card bookings get
  # the same arrival/started/meeting-ending pushes as the main create path.
  organize(
    Billing::Payment::UpdateUserPayment,
    Billing::Reservations::SaveRoomReservation,
    Billing::Reservations::RedeemBundlePass,
    Billing::Reservations::ChargeAtBooking,
    Reservations::ScheduleUpcomingReservationReminder,
    CreateNotificationsAsync,
    SendAdminNotificationForPaidRoom,
    Billing::Reservations::ScheduleReservationEmails
  )
end
