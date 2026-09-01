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
    # Non-payment cutoff runs FIRST (nothing persisted yet, nothing to roll
    # back): a payment-suspended member can't book self-serve. No-op unless
    # the caller sets enforce_payment_standing.
    Billing::Reservations::EnforcePaymentStanding,
    # Posted-hours backstop: member self-serve bookings stay inside the
    # location's posted hours. No-op unless the caller sets
    # enforce_posted_hours.
    Billing::Reservations::EnforcePostedHours,
    # Duration backstop, same shape (still nothing persisted): member
    # self-serve bookings can't exceed the room's bookable cap. No-op unless
    # the caller sets enforce_duration_cap.
    Billing::Reservations::EnforceDurationCap,
    Billing::Reservations::SaveRoomReservation,
    Billing::Reservations::ChargeCredits,
    # Commit day-pass coverage for an included room BEFORE ChargeAtBooking prices
    # the room + overage (ADR 0019): reuse a spare pass → burn a bundle pass →
    # buy one; EnforceCoverage blocks (422) if an included booking is still
    # uncovered. Each step no-ops unless its decision flag is set.
    Billing::Reservations::ReuseCoveragePass,
    Billing::Reservations::RedeemBundlePass,
    Billing::Reservations::BuyCoverageDayPass,
    Billing::Reservations::EnforceCoverage,
    # A metered pass's included-minutes cap is only enforceable as money when
    # the location has an overage rate; where the rate is $0 this blocks an
    # over-allowance booking instead of letting it through free.
    Billing::Reservations::EnforceMeteredRoomLimit,
    Billing::Reservations::ChargeAtBooking,
    Reservations::ScheduleUpcomingReservationReminder,
    CreateNotificationsAsync,
    SendAdminNotificationForPaidRoom,
    Billing::Reservations::ScheduleReservationEmails
  )
end
