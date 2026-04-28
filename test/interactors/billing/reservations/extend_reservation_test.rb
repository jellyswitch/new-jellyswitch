require "test_helper"

class Billing::Reservations::ExtendReservationTest < ActiveSupport::TestCase
  def test_organized_interactors
    expected_organized = [
      Billing::Reservations::UpdateReservationDuration,
      Billing::Reservations::ChargeCredits,
      Billing::Reservations::AuthorizeHold,
      Reservations::ScheduleSettleReservation,
    ]

    assert_equal expected_organized, Billing::Reservations::ExtendReservation.organized
  end
end
