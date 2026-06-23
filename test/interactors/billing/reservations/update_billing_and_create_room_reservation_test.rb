require 'test_helper'

class Billing::Reservations::UpdateBillingAndCreateRoomReservationTest < ActiveSupport::TestCase
  def test_organized_interactors
    # GrantFreeDayPass intentionally absent — paid bookings mint no comp pass (ADR 0012).
    expected_organized = [
      Billing::Payment::UpdateUserPayment,
      Billing::Reservations::SaveRoomReservation,
      Billing::Reservations::AuthorizeHold,
      Reservations::ScheduleSettleReservation,
      CreateNotificationsAsync,
      SendAdminNotificationForPaidRoom,
      Billing::Reservations::ScheduleReservationEmails
    ]

    assert_equal expected_organized, Billing::Reservations::UpdateBillingAndCreateRoomReservation.organized
  end
end
