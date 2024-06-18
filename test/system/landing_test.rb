require 'application_system_test_case'

class LandingTest < ApplicationSystemTestCase
  include ApplicationHelper

  setup do
    @user = users(:cowork_tahoe_member)
    @ongoing_reservation = reservations(:ongoing_room_reservation)

  end

  test "should display the user's ongoing reservation on the page" do
    log_in @user

    assert_text "Upcoming Reservation"
    assert_text long_date(@ongoing_reservation.datetime_in)
    assert_text @ongoing_reservation.room.name
  end

  test "should not display the section if the user's do not have any future/ongoing reservation" do
    log_in @user

    @user.reservations.future.destroy_all
    @user.reservations.ongoing.destroy_all

    assert_no_text "Upcoming Reservation"
  end
end
