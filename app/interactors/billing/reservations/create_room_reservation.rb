class Billing::Reservations::CreateRoomReservation
  include Interactor::Organizer

  # Billing flow (ADR 0010): paid reservations are CAPTURED AT BOOKING via
  # ChargeAtBooking (immediate-capture PaymentIntent for self-serve; net-30
  # send_invoice for out_of_band orgs) — no more authorize-hold-then-settle.
  # A card decline fails the booking and SaveRoomReservation#rollback destroys
  # the reservation so a declined attempt never holds the slot.
  # GrantFreeDayPass removed (ADR 0012): a paid-room booking no longer mints a
  # complimentary DayPass. Those comp passes carried included_meeting_room_minutes
  # that re-priced a later edit/room-switch through the day-pass overage branch
  # (the "Brad bug"). Building access for paid-room bookers comes from their
  # active reservation (User#allowed_in? → has_active_reservation?); Phase 4 will
  # narrow that to a ±window.
  organize(
    Billing::Reservations::SaveRoomReservation,
    Billing::Reservations::ChargeCredits,
    Billing::Reservations::RedeemBundlePass,
    Billing::Reservations::ChargeAtBooking,
    Reservations::ScheduleUpcomingReservationReminder,
    CreateNotificationsAsync,
    SendAdminNotificationForPaidRoom,
    Billing::Reservations::ScheduleReservationEmails
  )
end
