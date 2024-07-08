require "test_helper"

class ReservationTest < ActiveSupport::TestCase
  def setup
    @ongoing_reservation = reservations(:room_reservation)
    @ongoing_reservation.update(datetime_in: Time.zone.now)

    @ongoing_room = @ongoing_reservation.room

    User.any_instance.stubs(:should_charge_for_reservation?).returns(true)

    @amenity1 = Amenity.create(name: "Amenity 1", price: 10, room: @ongoing_room)
    @amenity2 = Amenity.create(name: "Amenity 2", price: 15, room: @ongoing_room)

    @future_reservation = reservations(:future_room_reservation)
  end

  def teardown
    @future_reservation.destroy
    @ongoing_reservation.destroy
  end

  test "associations" do
    assert_equal :has_and_belongs_to_many, Reservation.reflect_on_association(:amenities).macro
  end

  test "ongoing scope should return ongoing reservations" do
    ongoing_reservations = Reservation.ongoing

    assert_includes ongoing_reservations, @ongoing_reservation
    assert_not_includes ongoing_reservations, @future_reservation
  end

  test "datetime_out should return the datetime_in plus the minutes" do
    expected_datetime_out = @ongoing_reservation.datetime_in + @ongoing_reservation.minutes.minutes

    assert_equal @ongoing_reservation.datetime_out, expected_datetime_out
  end

  test "should return true for ongoing reservation" do
    assert @ongoing_reservation.ongoing?
  end

  test "should return true for future reservation" do
    assert @future_reservation.future?
  end

  test "end_now! updates the minutes to the actual duration" do
    new_duration = 12 # minutes

    Timecop.freeze(@ongoing_reservation.datetime_in + new_duration.minutes) do
      @ongoing_reservation.end_now!
      assert_equal @ongoing_reservation.reload.minutes, new_duration
      assert @ongoing_reservation.ended_early?
    end
  end

  test "end_now! does not change minutes if called after the original end time" do
    original_duration = @ongoing_reservation.minutes
    new_duration = original_duration + 5.minutes # minutes

    Timecop.freeze(@ongoing_reservation.datetime_in + new_duration.minutes) do
      @ongoing_reservation.end_now!
      assert_not_equal @ongoing_reservation.reload.minutes, new_duration
      assert_equal @ongoing_reservation.minutes, original_duration
      assert @ongoing_reservation.ended_early?
    end
  end

  test "room_price returns the price of the room when paid? is true" do
    @ongoing_room.update hourly_rate_in_cents: 1000
    @ongoing_reservation.update(
      paid: true,
      minutes: 180,
    )

    assert_equal @ongoing_reservation.room_price, (180 / 60) * 1000
  end

  test "room_price returns the 0 when paid? is false" do
    @ongoing_room.update hourly_rate_in_cents: 1000
    @ongoing_reservation.update(
      paid: false,
      minutes: 180,
    )

    assert_equal @ongoing_reservation.room_price, 0
  end

  test "amenity_price returns the total regular amenity price for non-members" do
    User.any_instance.stubs(:should_charge_for_reservation?).returns(true)
    @ongoing_reservation.amenities << [@amenity1, @amenity2]
    expected_price = (@amenity1.price + @amenity2.price) * 100

    assert_equal expected_price, @ongoing_reservation.amenity_price
  end

  test "amenity_price returns the total membership amenity price for members" do
    User.any_instance.stubs(:should_charge_for_reservation?).returns(false)
    @ongoing_reservation.amenities << [@amenity1, @amenity2]
    expected_price = (@amenity1.membership_price + @amenity2.membership_price) * 100

    assert_equal expected_price, @ongoing_reservation.amenity_price
  end

  test "charge_amount calculation with no amenities" do
    @ongoing_reservation.amenities.destroy_all

    expected_amount = ((@ongoing_reservation.room.hourly_rate_in_cents / 60.0) * @ongoing_reservation.minutes).to_i

    assert_equal @ongoing_reservation.charge_amount, expected_amount
  end

  test "charge_amount calculation with amenities" do
    room = @ongoing_reservation.room

    @ongoing_reservation.amenities << [@amenity1, @amenity2]

    room_charge = ((room.hourly_rate_in_cents / 60.0) * @ongoing_reservation.minutes).to_i
    amenity_charge = Money.from_amount(25, "USD").cents
    expected_amount = room_charge + amenity_charge

    assert_equal @ongoing_reservation.charge_amount, expected_amount
  end

  test "amenity_names returns a list of amenity names" do
    room = @ongoing_reservation.room
    room.update(av: true, whiteboard: true)

    @ongoing_reservation.amenities << [@amenity1, @amenity2]

    expected_names = ["Amenity 1", "Amenity 2", "AV Equipment", "Whiteboard"].join(", ")
    assert_equal @ongoing_reservation.amenity_names, expected_names
  end
end
