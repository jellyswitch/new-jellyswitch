module StripeHelper
  def setup_initial_user_fixtures
    @member = UserContext.new(users(:cowork_tahoe_member), operators(:cowork_tahoe), locations(:cowork_tahoe_location))
  end

  def setup_stripe
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

    #create office leases
    # office_lease_subscription = subscriptions(:cowork_tahoe_office_lease)


    # params = {
    #   customer: office_lease_subscription.billable.stripe_customer_id,
    #   items: [{ plan: office_lease_subscription.plan.stripe_plan_id }],
    #   prorate: false,
    #   billing_cycle_anchor: nil,
    #   billing: 'send_invoice',
    #   days_until_due: 30
    # }

    # stripe_subscription = operators(:cowork_tahoe).stripe_request('Subscription', :create, params)

    # office_lease_subscription.update(stripe_subscription_id: stripe_subscription.id)
  end
end