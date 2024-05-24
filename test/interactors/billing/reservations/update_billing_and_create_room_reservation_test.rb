require 'test_helper'

class Billing::Reservations::UpdateBillingAndCreateRoomReservationTest < ActiveSupport::TestCase
  def test_organized_interactors
    expected_organized = [
      Billing::Payment::UpdateUserPayment,
      Billing::Reservations::SaveRoomReservation,
      Billing::Reservations::SaveStripeInvoice,
      Billing::Reservations::GrantFreeDayPass,
      CreateNotificationsAsync,
      SendAdminNotificationForPaidRoom
    ]

    assert_equal expected_organized, Billing::Reservations::UpdateBillingAndCreateRoomReservation.organized
  end
end
