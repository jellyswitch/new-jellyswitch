class Operator::PauseMembershipsController < Operator::BaseController
  include SubscriptionsHelper

  def update
    find_subscription

    if pause_durations.include?(params["resumes_at"])
      resumes_at = ((@subscription.current_period_end - 1.day) + params["resumes_at"].to_i.days)
    else
      resumes_at = nil
    end

    result = SetMembershipToPause.call(
      subscription: @subscription,
      resumes_at: resumes_at
    )

    if result.success?
      if resumes_at == nil
        flash[:success] = "You have scheduled your membership '#{@subscription.plan.name}' to pause indefinitely, starting at end of your current period"
      else
        flash[:success] = "You have scheduled your membership '#{@subscription.plan.name}' to pause for #{params["resumes_at"]} days, starting at the end of your current period"
      end
      turbo_redirect home_path
    else
      flash[:error] = result.message
      turbo_redirect subscription_path(@subscription)
    end
  end

  def destroy
    find_subscription

    result = UnpauseMembership.call(
      subscription: @subscription
    )

    if result.success?
      flash[:success] = "Your subscription has been unpaused '#{@subscription.plan.name}'"
      turbo_redirect subscription_path(@subscription)
    else
      flash[:error] = result.message
      turbo_redirect subscription_path(@subscription)
    end
  end

  private

  def pause_durations
    ["30", "60", "90"]
  end

end