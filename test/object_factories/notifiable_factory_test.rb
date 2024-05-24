require 'test_helper'

class NotifiableFactoryTest < ActiveSupport::TestCase
  def setup
    @reservation = reservations(:room_reservation)
    @subscription = subscriptions(:cowork_tahoe_subscription)
  end

  test "returns correct notifiable instance for given type" do
    notifiable_instance = NotifiableFactory.for(@reservation, 'PaidRoomReservation')
    assert_instance_of Notifiable::PaidRoomReservation, notifiable_instance

    notifiable_instance = NotifiableFactory.for(@subscription, 'Subscription')
    assert_instance_of Notifiable::Subscription, notifiable_instance
  end

  test "returns correct notifiable instance based on class name if type is not passed" do
    notifiable_instance = NotifiableFactory.for(@subscription)
    assert_instance_of Notifiable::Subscription, notifiable_instance

    notifiable_instance = NotifiableFactory.for(@reservation)
    assert_instance_of Notifiable::Reservation, notifiable_instance
  end

  test "raises error for unknown notifiable type" do
    exception = assert_raises(RuntimeError) do
      NotifiableFactory.for(@reservation, 'UnknownType')
    end

    assert_equal "Unknown notifiable type: UnknownType", exception.message
  end
end
