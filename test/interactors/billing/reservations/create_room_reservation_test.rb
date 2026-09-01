require "test_helper"

class Billing::Reservations::CreateRoomReservationTest < ActiveSupport::TestCase
  # Captured at booking (ADR 0010): ChargeAtBooking replaces the hold/settle
  # pair. RedeemBundlePass (ADR 0015) runs after Save, before ChargeAtBooking, so
  # an opted-in bundle pass mints a DayPass that zeroes the charge. GrantFreeDayPass
  # stays absent (ADR 0012) — paid bookings mint no complimentary day pass.
  # EnforcePaymentStanding runs FIRST (non-payment cutoff, ADR 0028), then
  # EnforcePostedHours (member self-serve posted-hours backstop, Nash incident
  # 2026-08-07) — nothing is persisted yet, so a violation fails fast with
  # nothing to roll back.
  def test_organized_interactors
    expected_organized = [
      Billing::Reservations::EnforcePaymentStanding,
      Billing::Reservations::EnforcePostedHours,
      Billing::Reservations::EnforceDurationCap,
      Billing::Reservations::SaveRoomReservation,
      Billing::Reservations::ChargeCredits,
      Billing::Reservations::ReuseCoveragePass,
      Billing::Reservations::RedeemBundlePass,
      Billing::Reservations::BuyCoverageDayPass,
      Billing::Reservations::EnforceCoverage,
      Billing::Reservations::EnforceMeteredRoomLimit,
      Billing::Reservations::ChargeAtBooking,
      Reservations::ScheduleUpcomingReservationReminder,
      CreateNotificationsAsync,
      SendAdminNotificationForPaidRoom,
      Billing::Reservations::ScheduleReservationEmails,
    ]

    assert_equal expected_organized, Billing::Reservations::CreateRoomReservation.organized
  end
end
