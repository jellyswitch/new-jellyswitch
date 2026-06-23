class Billing::Reservations::CreateRoomReservation
  include Interactor::Organizer

  # Billing flow (Apr 2026): paid reservations place a Stripe
  # PaymentIntent hold (AuthorizeHoldOrSchedule — immediate for close
  # bookings, deferred to ~6 days before start for far-future ones to
  # stay inside Stripe's ~7-day manual-capture window). The hold is
  # captured at datetime_in (SettleReservationJob), since by then
  # cancellation is closed (1-min cutoff).
  # GrantFreeDayPass removed (ADR 0012): a paid-room booking no longer mints a
  # complimentary DayPass. Those comp passes carried included_meeting_room_minutes
  # that re-priced a later edit/room-switch through the day-pass overage branch
  # (the "Brad bug"). Building access for paid-room bookers comes from their
  # active reservation (User#allowed_in? → has_active_reservation?); Phase 4 will
  # narrow that to a ±window. Removal is safe before Phase 4 precisely because
  # that all-day reservation grant still lets them in.
  organize(
    Billing::Reservations::SaveRoomReservation,
    Billing::Reservations::ChargeCredits,
    Billing::Reservations::AuthorizeHoldOrSchedule,
    Reservations::ScheduleSettleReservation,
    Reservations::ScheduleUpcomingReservationReminder,
    CreateNotificationsAsync,
    SendAdminNotificationForPaidRoom,
    Billing::Reservations::ScheduleReservationEmails
  )
end
