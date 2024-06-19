require "test_helper"
require "stripe_mock"

class ReservationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:cowork_tahoe_admin)

    @reservation = reservations(:future_room_reservation)
  end

  test "should cancel reservation successfully" do
    log_in @admin
    CancelReservation.stubs(:call).returns(OpenStruct.new(success?: true))

    delete reservation_path(@reservation), env: default_env

    assert :success
    assert_redirected_to root_path
    assert_equal "Reservation cancelled.", flash[:notice]
  end

  test "should return error message when cancel reservation failed" do
    log_in @admin

    expected_message = "Unable to cancel reservation."
    CancelReservation.stubs(:call).returns(OpenStruct.new(success?: false, message: expected_message))

    delete reservation_path(@reservation), env: default_env

    assert_equal expected_message, flash[:error]
  end
end
