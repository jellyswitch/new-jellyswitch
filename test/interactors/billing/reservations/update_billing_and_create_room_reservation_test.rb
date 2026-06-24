require 'test_helper'

class Billing::Reservations::UpdateBillingAndCreateRoomReservationTest < ActiveSupport::TestCase
  def test_organized_interactors
    # Captured at booking (ADR 0010): ChargeAtBooking replaces AuthorizeHold +
    # ScheduleSettleReservation. RedeemBundlePass (ADR 0015) runs before it.
    # GrantFreeDayPass stays absent (ADR 0012).
    expected_organized = [
      Billing::Payment::UpdateUserPayment,
      Billing::Reservations::SaveRoomReservation,
      Billing::Reservations::RedeemBundlePass,
      Billing::Reservations::ChargeAtBooking,
      CreateNotificationsAsync,
      SendAdminNotificationForPaidRoom,
      Billing::Reservations::ScheduleReservationEmails
    ]

    assert_equal expected_organized, Billing::Reservations::UpdateBillingAndCreateRoomReservation.organized
  end
end
