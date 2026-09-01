class Billing::Reservations::UpdateBillingAndCreateRoomReservation
  include Interactor::Organizer

  # New-card-on-booking flow: attach the card to the customer, then
  # CAPTURE AT BOOKING via ChargeAtBooking (ADR 0010), the same path as
  # CreateRoomReservation. GrantFreeDayPass removed (ADR 0012) — paid bookings
  # mint no comp pass. See CreateRoomReservation for the full rationale.
  # ScheduleUpcomingReservationReminder added in Phase 6 so new-card bookings get
  # the same arrival/started/meeting-ending pushes as the main create path.
  organize(
    # Non-payment cutoff first — parity with CreateRoomReservation; no-op
    # unless the caller sets enforce_payment_standing (member self-serve only).
    Billing::Reservations::EnforcePaymentStanding,
    # Posted-hours backstop — same shape.
    Billing::Reservations::EnforcePostedHours,
    # Duration backstop, same shape — before UpdateUserPayment, so an over-cap
    # request dies without attaching a card to the customer. No-op unless the
    # caller sets enforce_duration_cap.
    Billing::Reservations::EnforceDurationCap,
    Billing::Payment::UpdateUserPayment,
    Billing::Reservations::SaveRoomReservation,
    # Included-room coverage (ADR 0019) — parity with CreateRoomReservation, in
    # the same slot (after the reservation saves, before ChargeAtBooking prices
    # the room + overage). Each step no-ops unless its decision flag is set;
    # EnforceCoverage only blocks when the caller passes enforce_coverage: true.
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
