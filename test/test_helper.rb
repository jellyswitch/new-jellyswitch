ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "minitest/mock"
require "policy_assertions"
require "minitest/unit"
require "mocha/minitest"
require_relative './clearance_helper'
require_relative './stripe_helper'

class ActiveSupport::TestCase
  include StripeHelper
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

  def setup_initial_user_fixtures
    @admin = UserContext.new(users(:cowork_tahoe_admin), operators(:cowork_tahoe), locations(:cowork_tahoe_location))
    @member = UserContext.new(users(:cowork_tahoe_member), operators(:cowork_tahoe), locations(:cowork_tahoe_location))
    @community_manager = UserContext.new(users(:cowork_tahoe_community_manager), operators(:cowork_tahoe), locations(:cowork_tahoe_location))
    @general_manager = UserContext.new(users(:cowork_tahoe_general_manager), operators(:cowork_tahoe), locations(:cowork_tahoe_location))
    @superadmin = UserContext.new(users(:cowork_tahoe_superadmin), operators(:cowork_tahoe), locations(:cowork_tahoe_location))
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
  include ClearanceHelper
  include StripeHelper

  def default_env
    @default_env ||= { 'HTTP_USER_AGENT' => 'Something safari something else' }
  end

  def ios_env
    @default_env ||= { 'HTTP_USER_AGENT' => 'something Jellyswitch something else deviceToken: abcdef12345' }
  end
end

# reindex models
# [Announcement, Room, Door, Location, Organization, FeedItem, User].map {|klass| klass.reindex }

# and disable callbacks
Searchkick.disable_callbacks
