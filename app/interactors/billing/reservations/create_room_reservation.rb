class Billing::Reservations::CreateRoomReservation
  include Interactor::Organizer

  # Billing flow (Apr 2026): paid reservations place a Stripe
  # PaymentIntent hold (AuthorizeHoldOrSchedule — immediate for close
  # bookings, deferred to ~6 days before start for far-future ones to
  # stay inside Stripe's ~7-day manual-capture window). The hold is
  # captured at datetime_in (SettleReservationJob), since by then
  # cancellation is closed (1-min cutoff).
  organize(
    Billing::Reservations::SaveRoomReservation,
    Billing::Reservations::ChargeCredits,
    Billing::Reservations::AuthorizeHoldOrSchedule,
    Billing::Reservations::GrantFreeDayPass,
    Reservations::ScheduleSettleReservation,
    Reservations::ScheduleUpcomingReservationReminder,
    CreateNotificationsAsync,
    SendAdminNotificationForPaidRoom,
    Billing::Reservations::ScheduleReservationEmails
  )
end
