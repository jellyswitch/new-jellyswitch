require 'test_helper'

class ReservableFactoryTest < ActiveSupport::TestCase
  setup do
    @reservation = reservations(:room_reservation)
    @user = @reservation.user
  end

  test 'returns an instance of Reservable::OutOfBand if user payment method is out of band' do
    @user.stubs(:out_of_band?).returns(true)

    reservable = ReservableFactory.for(@reservation)

    assert_instance_of Reservable::OutOfBand, reservable
  end

  test 'returns an instance of Reservable::OutOfBand if user payment method is not out of band and is not card_added' do
    @user.stubs(:out_of_band?).returns(false)
    @user.stubs(:card_added?).returns(false)

    reservable = ReservableFactory.for(@reservation)

    assert_instance_of Reservable::OutOfBand, reservable
  end

  test 'returns an instance of Reservable::InBand if user is card_added is true' do
    @user.stubs(:out_of_band?).returns(false)
    @user.stubs(:card_added?).returns(true)

    reservable = ReservableFactory.for(@reservation)

    assert_instance_of Reservable::InBand, reservable
  end
end
