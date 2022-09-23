ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "minitest/mock"

class ActiveSupport::TestCase
  # Run tests in parallel with specified workers
  parallelize(workers: :number_of_processors)
  
  # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
  fixtures :all

  parallelize_setup do |worker|
    Searchkick.index_suffix = worker

    # reindex models
    # [Announcement, Room, Door, Location, Organization, FeedItem, User].map {|klass| klass.reindex }

    # and disable callbacks
    Searchkick.disable_callbacks
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
  end
end

class ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  def default_env
    @default_env ||= { 'HTTP_USER_AGENT' => 'Something safari something else' }
  end

  def ios_env
    @default_env ||= { 'HTTP_USER_AGENT' => 'something Jellyswitch something else deviceToken: abcdef12345' }
  end

  def log_in(user)
    user.update(password: 'password')
    ActsAsTenant.default_tenant = user.operator
    post login_path( params: { session: { email: user.email, password: 'password' } } )
  end
end

# reindex models
# [Announcement, Room, Door, Location, Organization, FeedItem, User].map {|klass| klass.reindex }

# and disable callbacks
Searchkick.disable_callbacks
