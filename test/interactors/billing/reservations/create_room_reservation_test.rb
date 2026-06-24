require "test_helper"

class Billing::Reservations::CreateRoomReservationTest < ActiveSupport::TestCase
  # Captured at booking (ADR 0010): ChargeAtBooking replaces the hold/settle
  # pair (AuthorizeHoldOrSchedule + ScheduleSettleReservation). GrantFreeDayPass
  # stays absent (ADR 0012) — paid bookings mint no complimentary day pass.
  def test_organized_interactors
    expected_organized = [
      Billing::Reservations::SaveRoomReservation,
      Billing::Reservations::ChargeCredits,
      Billing::Reservations::ChargeAtBooking,
      Reservations::ScheduleUpcomingReservationReminder,
      CreateNotificationsAsync,
      SendAdminNotificationForPaidRoom,
      Billing::Reservations::ScheduleReservationEmails,
    ]

    assert_equal expected_organized, Billing::Reservations::CreateRoomReservation.organized
  end
end
