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

  test "returns TourRequestAlert instance for type 'TourRequestAlert'" do
    setup_initial_user_fixtures
    operator = operators(:cowork_tahoe)
    location = operator.locations.first
    requester = User.create!(
      email: "req+factory@example.com", name: "Req Factory", operator: operator,
      original_location_id: location.id, admin_created: true,
      password: "tempPass1!", phone: "555-0002",
    )
    activity = Activity.create!(
      user: requester, operator: operator, kind: "tour_request",
      occurred_at: Time.current, subject: location, payload: { "message" => "hi" },
    )

    notifiable = NotifiableFactory.for(activity, "TourRequestAlert")

    assert_instance_of Notifiable::TourRequestAlert, notifiable
  end
end
