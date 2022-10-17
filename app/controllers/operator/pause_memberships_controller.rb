class Operator::PauseMembershipsController < Operator::BaseController
  include SubscriptionsHelper

  def create
    find_subscription

    if pause_durations.has_key?(params["resumes_at"])
      resumes_at = pause_durations[params["resumes_at"]].to_i
    else
      resumes_at = nil
    end

    result = CreatePause.call(
      subscription: @subscription,
      resumes_at: resumes_at,
      notifiable: current_tenant.users.admins,
      operator: current_tenant,
      user: current_tenant.users.admins.first,
      blob: { text: "#{@subscription.subscribable.name} paused their membership.", type: "membership_paused" }
    )

    def days(resumes_at)
      begin_date = Time.now
      end_date = Time.at(resumes_at)
      (end_date - begin_date) / (60 * 60 * 24)
    end

    if result.success?
      if resumes_at == nil
        flash[:success] = "You have paused your subscription '#{@subscription.plan.name}'"
      else
        flash[:success] = "You have paused your subscription '#{@subscription.plan.name}' for #{days(resumes_at).round} days"
      end
      turbo_redirect home_path
    else
      flash[:error] = result.message
      turbo_redirect subscription_path(@subscription)
    end
  end

  def destroy
    find_subscription

    result = DestroyPause.call(
      subscription: @subscription,
      notifiable: current_tenant.users.admins,
      operator: current_tenant,
      user: current_tenant.users.admins.first,
      blob: { text: "#{@subscription.subscribable.name} un-paused their membership.", type: "membership_unpaused" }
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
    {
      "30" => (Time.current.to_i + 30.days),
      "60" => (Time.current.to_i + 60.days),
      "90" => (Time.current.to_i + 90.days)
    }
  end

end