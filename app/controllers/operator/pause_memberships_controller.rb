class Operator::PauseMembershipsController < Operator::BaseController
  include SubscriptionsHelper

  def create
    find_subscription

    if params["resumes_at"].present?
      resumes_at = params["resumes_at"].to_i
    else
      resumes_at = nil
    end

    result = PauseMembership.call(
      subscription: @subscription,
      resumes_at: resumes_at
    )

    if result.success?
      flash[:success] = "You have paused your subscription '#{@subscription.plan.name}'"
      turbo_redirect subscription_path(@subscription)
    else
      flash[:error] = "Something went wrong pausing your subscription '#{@subscription.plan.name}'"
      turbo_redirect subscription_path(@subscription)
    end
  end

  def destroy
    find_subscription

    result = UnpauseMembership.call(
      subscription: @subscription
    )

    if result.success?
      flash[:success] = "Your subscription has been reactivated '#{@subscription.plan.name}'"
      turbo_redirect subscription_path(@subscription)
    else
      flash[:error] = "Something went wrong unpausing your subscription '#{@subscription.plan.name}'"
      turbo_redirect subscription_path(@subscription)
    end
  end

end