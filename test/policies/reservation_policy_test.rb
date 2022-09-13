require "test_helper"

class ReservationPolicyTest < PolicyAssertions::Test

  setup do
    setup_initial_user_fixtures
  end

  def test_new
    assert_permit @member, Reservation
    assert_permit @admin, Reservation
    assert_permit @community_manager, Reservation
    assert_permit @general_manager, Reservation
  end

  def test_create
    assert_permit @member, Reservation
    assert_permit @admin, Reservation
    assert_permit @community_manager, Reservation
    assert_permit @general_manager, Reservation
  end

  def test_show
    assert_permit @member, reservations(:room_reservation)
    assert_permit @admin, reservations(:room_reservation)
    assert_permit @community_manager, reservations(:room_reservation)
    assert_permit @general_manager, reservations(:room_reservation)
  end

  def test_destroy
    assert_permit @member, Reservation
    assert_permit @admin, Reservation
    assert_permit @community_manager, Reservation
    assert_permit @general_manager, Reservation
  end

  def test_cancel
    assert_not_permitted @member, reservations(:room_reservation)
    assert_permit @admin, reservations(:room_reservation)
    assert_permit @community_manager, reservations(:room_reservation)
    assert_permit @general_manager, reservations(:room_reservation)
  end

  def test_long_duration
    assert_not_permitted @member, Reservation
    assert_permit @admin, Reservation
    assert_permit @community_manager, Reservation
    assert_permit @general_manager, Reservation
  end

  def test_today
    assert_not_permitted @member, Reservation
    assert_permit @admin, Reservation
    assert_permit @community_manager, Reservation
    assert_permit @general_manager, Reservation
  end
end