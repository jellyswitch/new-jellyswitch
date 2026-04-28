class Billing::Reservations::CreateRoomReservation
  include Interactor::Organizer

  # Billing flow (Oct 2026): paid reservations place a Stripe
  # PaymentIntent hold at booking time (AuthorizeHold). The actual
  # amount is captured when the reservation ends (end_now or
  # SettleReservationJob at datetime_out). This means users only pay
  # for the time they actually used.
  organize(
    Billing::Reservations::SaveRoomReservation,
    Billing::Reservations::ChargeCredits,
    Billing::Reservations::AuthorizeHold,
    Billing::Reservations::GrantFreeDayPass,
    Reservations::ScheduleSettleReservation,
    Reservations::ScheduleUpcomingReservationReminder,
    CreateNotificationsAsync,
    SendAdminNotificationForPaidRoom,
    Billing::Reservations::ScheduleReservationEmails
  )
end
