require "test_helper"
require "rake"

class UpdateReservationPaidStatusTest < ActiveSupport::TestCase
  def setup
    Rails.application.load_tasks
    @future_reservation = reservations(:future_room_reservation)
    @past_reservation = reservations(:room_reservation)
  end

  test "update_paid_status updates only future reservations" do
    # Ensure reservations are in a known state
    @future_reservation.update_column(:paid, nil)
    @past_reservation.update_column(:paid, nil)

    # Mock the is_charged? method
    Reservation.any_instance.stubs(:is_charged?).returns(true)

    # Run the rake task
    Rake::Task["reservations:update_paid_status"].invoke

    # Reload the reservations from the database
    @future_reservation.reload
    @past_reservation.reload

    assert_equal @future_reservation.paid, true
    assert_nil @past_reservation.paid
  end
end
