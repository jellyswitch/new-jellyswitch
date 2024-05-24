require 'test_helper'

class Billing::Reservations::CreateRoomReservationTest < ActiveSupport::TestCase
  def test_organized_interactors
    expected_organized = [
      Billing::Reservations::SaveRoomReservation,
      Billing::Reservations::ChargeCredits,
      Billing::Reservations::SaveStripeInvoice,
      Billing::Reservations::GrantFreeDayPass,
      CreateNotificationsAsync,
      SendAdminNotificationForPaidRoom
    ]

    assert_equal expected_organized, Billing::Reservations::CreateRoomReservation.organized
  end
end
