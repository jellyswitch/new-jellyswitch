class Operator::Admin::SubscriptionsController < Operator::BaseController
  include SubscriptionsHelper

  def create
    authorize Subscription, :new?

    @subscription = new_subscription

    start_day = nil

    if params[:subscription][:start_day].present?
      start_day = Time.zone.at(params[:subscription][:start_day].to_i) + 2.hours
    end

    out_of_band = params[:out_of_band] || @subscription.subscribable.out_of_band

    result = CreateSubscription.call(
      subscription: @subscription,
      token: params[:stripeToken],
      user: @subscription.subscribable,
      start_day: start_day,
      out_of_band: out_of_band
    )

    if result.success?
      flash[:success] = "Membership created."
      turbolinks_redirect(user_path(@subscription.user))
    else
      flash[:error] = result.message
      turbolinks_redirect(referrer_or_root)
    end
  rescue => e
    Rollbar.error(e)
    flash[:error] = "An error occurred: #{e.message}"
    turbolinks_redirect(referrer_or_root)
  end

  private

  def subscription_params
    params.require(:subscription).permit(:plan_id, :subscribable_id)
  end

  def new_subscription
    subscribable = User.find(subscription_params[:subscribable_id])
    subscription = Subscription.new(subscription_params)
    subscription.active = true
    subscription.subscribable = subscribable
    subscription
  end
end