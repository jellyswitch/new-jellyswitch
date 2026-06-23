require "test_helper"

class Billing::Reservations::CreateRoomReservationTest < ActiveSupport::TestCase
  # GrantFreeDayPass is intentionally absent (ADR 0012): paid bookings mint no
  # complimentary day pass. This locks the "Brad bug" fix at the organizer level.
  def test_organized_interactors
    expected_organized = [
      Billing::Reservations::SaveRoomReservation,
      Billing::Reservations::ChargeCredits,
      Billing::Reservations::AuthorizeHoldOrSchedule,
      Reservations::ScheduleSettleReservation,
      Reservations::ScheduleUpcomingReservationReminder,
      CreateNotificationsAsync,
      SendAdminNotificationForPaidRoom,
      Billing::Reservations::ScheduleReservationEmails,
    ]

    assert_equal expected_organized, Billing::Reservations::CreateRoomReservation.organized
  end
end
