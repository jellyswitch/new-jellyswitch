class Operator::PauseMembershipsController < Operator::BaseController
  include SubscriptionsHelper

  def create
    find_subscription

    @subscription.update(paused: true)

    Stripe.api_key = ENV['STRIPE_TEST_SECRET_KEY']
    Stripe::Subscription.update(
      @subscription.stripe_subscription_id,
      { pause_collection: { behavior: 'void' } },
    )

    flash[:success] = "You have paused your subscription '#{@subscription.plan.name}'"

    turbo_redirect subscription_path(@subscription)
  end

  def destroy
    find_subscription

    @subscription.update(paused: false)

    Stripe.api_key = ENV['STRIPE_TEST_SECRET_KEY']
    Stripe::Subscription.update(
    @subscription.stripe_subscription_id,
      {
        pause_collection: ''
      }
    )


    flash[:success] = "Your subscription has been reactivated '#{@subscription.plan.name}'"

    turbo_redirect subscription_path(@subscription)
  end
end