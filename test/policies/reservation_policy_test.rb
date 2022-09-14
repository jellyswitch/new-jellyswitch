require "test_helper"
require "stripe_mock"

class ReservationPolicyTest < PolicyAssertions::Test

  def stripe_helper
    StripeMock.create_test_helper
  end

  setup do
    setup_initial_user_fixtures
    StripeMock.start
    @subscription = subscriptions(:cowork_tahoe_subscription)
    @plan = plans(:cowork_tahoe_full_time_plan)
    @operator = operators(:cowork_tahoe)

    customer = Stripe::Customer.create({
                                         email: @member.user.email
                                       }, {
                                         api_key: @operator.stripe_secret_key,
                                         stripe_account: @operator.stripe_user_id
                                       })

    plan = Stripe::Plan.create({
                                 amount: @plan.amount_in_cents,
                                 interval: @plan.stripe_interval,
                                 interval_count: @plan.stripe_interval_count,
                                 product: { name: @plan.plan_name },
                                 currency: 'usd',
                                 id: @plan.slug
                               })

    subscription = Stripe::Subscription.create({
                                            customer: customer.id,
                                            plan: @plan.plan_name
                                          }, {
                                            api_key: @operator.stripe_secret_key,
                                            stripe_account: @operator.stripe_user_id
                                          })

    @subscription.update(stripe_subscription_id: subscription.id)




    @member.user.update(stripe_customer_id: customer.id)
    @subscription.update(stripe_subscription_id: plan.id)
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
    byebug
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