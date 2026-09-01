require 'test_helper'

class Billing::Reservations::UpdateBillingAndCreateRoomReservationTest < ActiveSupport::TestCase
  def test_organized_interactors
    # Captured at booking (ADR 0010): ChargeAtBooking replaces AuthorizeHold +
    # ScheduleSettleReservation. GrantFreeDayPass stays absent (ADR 0012).
    # ADR 0019 (web P8): the full included-room coverage set — reuse spare / burn
    # bundle / buy / enforce — runs after SaveRoomReservation and before
    # ChargeAtBooking, parity with CreateRoomReservation, so the new-card web path
    # commits coverage the same way the no-card path does.
    # EnforcePaymentStanding runs FIRST (non-payment cutoff, ADR 0028), then
    # EnforcePostedHours (member self-serve posted-hours backstop, Nash
    # incident 2026-08-07) — both before the card attach, so a blocked
    # attempt fails without touching the customer's payment method.
    expected_organized = [
      Billing::Reservations::EnforcePaymentStanding,
      Billing::Reservations::EnforcePostedHours,
      Billing::Reservations::EnforceDurationCap,
      Billing::Payment::UpdateUserPayment,
      Billing::Reservations::SaveRoomReservation,
      Billing::Reservations::ReuseCoveragePass,
      Billing::Reservations::RedeemBundlePass,
      Billing::Reservations::BuyCoverageDayPass,
      Billing::Reservations::EnforceCoverage,
      Billing::Reservations::EnforceMeteredRoomLimit,
      Billing::Reservations::ChargeAtBooking,
      Reservations::ScheduleUpcomingReservationReminder,
      CreateNotificationsAsync,
      SendAdminNotificationForPaidRoom,
      Billing::Reservations::ScheduleReservationEmails
    ]

    assert_equal expected_organized, Billing::Reservations::UpdateBillingAndCreateRoomReservation.organized
  end
end
