require 'test_helper'

class UserManagerTest < ActiveSupport::TestCase
  setup do
    @user = users(:cowork_tahoe_member)
    @old_user = @user.dup

    StripeMock.start

    @stripe_helper = StripeMock.create_test_helper
    
    # create plans in stripe
    [:cowork_tahoe_part_time_plan, :cowork_tahoe_full_time_plan].map do |plan_sym|
      plan = plans(plan_sym)

      product = Stripe::Product.create({ name: plan.plan_name, type: 'service' })

      stripe_plan = @stripe_helper.create_plan(
        amount: plan.amount_in_cents,
        interval: plan.stripe_interval,
        interval_count: plan.stripe_interval_count,
        product: product.id,
        currency: 'usd',
        id: plan.plan_slug
      )

      plan.update(stripe_plan_id: stripe_plan.id)
    end

    customer = Stripe::Customer.create({ email: @user.email })
    @user.update(stripe_customer_id: customer.id)
    
    # create subscriptions in stripe
    subscription = subscriptions(:cowork_tahoe_subscription)

    
    params = {
      customer: subscription.billable.stripe_customer_id,
      items: [{ plan: subscription.plan.stripe_plan_id }],
      prorate: false,
      billing_cycle_anchor: nil,
      billing: 'send_invoice',
      days_until_due: 30
    }
    
    stripe_subscription = operators(:cowork_tahoe).stripe_request('Subscription', :create, params)

    subscription.update(stripe_subscription_id: stripe_subscription.id)
  end

  teardown do
    StripeMock.stop
  end

  test 'it scrubs personally identifiable info from the user record' do
    UserManager.new(user: @user).ready
    @user.reload

    assert @user.name != @old_user.name
    assert @user.email != @old_user.email


    [:bio, :linkedin, :twitter, :website, :phone, :stripe_customer_id, :organization_id].map do |attr|
      assert @user.send(attr).blank?
    end
  end

  test 'it removes all future reservations' do
    assert @user.reservations.future.count > 0
    UserManager.new(user: @user).ready
    @user.reload

    assert @user.reservations.future.count < 1
  end

  test 'it removes all active memberships' do
    assert @user.subscriptions.active.count > 0

    UserManager.new(user: @user).ready
    @user.reload

    assert @user.subscriptions.active.count < 1
  end

  test 'it fails if the user is a group owner' do
    
  end

  test 'it creates a feed item for admins' do

  end

  test 'it archives the user' do

  end

  test 'it rolls back in case of a stripe API exception' do

  end
end