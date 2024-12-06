require "test_helper"

class Billing::Reservations::SaveRoomReservationTest < ActiveSupport::TestCase
  def setup
    @user = users(:cowork_tahoe_member)
    @room = rooms(:small_meeting_room)

    @datetime_in = Time.current + 10.day

    @reservation_params = {
      room_id: @room.id,
      datetime_in: @datetime_in,
      user_id: @user.id,
      minutes: 60,
    }
  end

  test "successfully creates a reservation" do
    result = Billing::Reservations::SaveRoomReservation.call(reservation_params: @reservation_params, user: @user)

    assert result.success?
    assert result.reservation.persisted?

    assert_equal @room, result.reservation.room
    assert_equal @user, result.reservation.user
    assert_equal @datetime_in, result.reservation.datetime_in
    assert_equal 60, result.reservation.minutes
  end

  test "sets paid to true if user should be charged and room price is more than 0" do
    @room.update(hourly_rate_in_cents: 100)
    @user.stubs(:should_charge_for_reservation?).returns(true)

    result = Billing::Reservations::SaveRoomReservation.call(reservation_params: @reservation_params, user: @user)

    assert result.success?
    assert result.reservation.paid?
  end

  test "sets paid to false if user should not be charged" do
    @user.stubs(:should_charge_for_reservation?).returns(false)

    result = Billing::Reservations::SaveRoomReservation.call(reservation_params: @reservation_params, user: @user)

    assert result.success?
    refute result.reservation.paid?
  end

  test "sets paid to false if the room is free" do
    @room.update(hourly_rate_in_cents: 0)
    @user.stubs(:should_charge_for_reservation?).returns(false)

    result = Billing::Reservations::SaveRoomReservation.call(reservation_params: @reservation_params, user: @user)

    assert result.success?
    refute result.reservation.paid?
  end

  test "fails when reservation is invalid" do
    Reservation.any_instance.stubs(:save).returns(false)

    context = Billing::Reservations::SaveRoomReservation.call(
      user: @user,
      reservation_params: @reservation_params,
    )

    assert context.failure?
    assert_equal "Unable to create reservation, please try again.", context.message
    refute context.reservation&.persisted?
  end
end
