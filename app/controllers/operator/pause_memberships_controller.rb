class Operator::PauseMembershipsController < Operator::BaseController
  include SubscriptionsHelper

  def create
    find_subscription

    if pause_durations.has_key?(params["resumes_at"])
      resumes_at = pause_durations[params["resumes_at"]].to_i
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

  private

  def pause_durations
    {
      "30" => (Time.current.to_i + 30.days),
      "60" => (Time.current.to_i + 60.days),
      "90" => (Time.current.to_i + 90.days)
    }
  end

end