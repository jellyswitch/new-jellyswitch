class Operator::Admin::SubscriptionsController < Operator::BaseController
  include SubscriptionsHelper

  def create
    authorize Subscription, :new?

    @subscription = new_subscription
    start_day = compute_start_day
    out_of_band = params[:out_of_band] || @subscription.subscribable.out_of_band

    interactor = Billing::Subscription::CreateSubscription
    
    if out_of_band == false && @subscription.subscribable.card_added == false
      interactor = Billing::Subscription::CreatePendingSubscription
    end
    
    result = interactor.call(
      subscription: @subscription,
      token: params[:stripeToken],
      user: @subscription.subscribable,
      start_day: start_day,
      out_of_band: out_of_band,
      operator: current_tenant
    )

    if result.success?
      flash[:success] = "Membership created."
      turbolinks_redirect(user_path(@subscription.subscribable))
    else
      flash[:error] = result.message
      turbolinks_redirect(referrer_or_root)
    end
  #rescue => e
  #  Rollbar.error(e)
  #  flash[:error] = "An error occurred: #{e.message}"
  #  turbolinks_redirect(referrer_or_root)
  end

  def destroy
    find_subscription
    authorize @subscription

    result = Billing::Subscription::CancelPendingSubscription.call(
      subscription: @subscription
    )

    if result.success?
      flash[:success] = "Membership cancelled."
      turbolinks_redirect(user_path(@subscription.subscribable))
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