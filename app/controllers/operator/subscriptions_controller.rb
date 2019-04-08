class Operator::SubscriptionsController < Operator::BaseController
  def new
    @subscription = Subscription.new
    authorize @subscription
    background_image
    include_stripe
  end

  def create
    authorize Subscription, :new?

    if admin?
      @subscription = new_admin_subscription
    else
      @subscription = new_subscription
    end

    start_day = nil

    if params[:subscription][:start_day].present?
      start_day = Time.zone.at(params[:subscription][:start_day].to_i) + 2.hours
    end

    result = CreateSubscription.call(
      subscription: @subscription,
      token: params[:stripeToken],
      user: @subscription.subscribable,
      start_day: start_day
    )

    if result.success?
      flash[:success] = "Welcome to #{current_tenant.name}!"
      turbolinks_redirect(root_path)
    else
      flash[:error] = result.message
      turbolinks_redirect(referrer_or_root)
    end
  rescue Exception => e
    Rollbar.error(e)
    flash[:error] = "An error occurred: #{e.message}"
    turbolinks_redirect(referrer_or_root)
  end

  def edit
    find_subscription
    authorize @subscription
    background_image
  end

  def update
    find_subscription
    authorize @subscription
    @new_subscription = new_subscription

    result = SwitchMembership.call(
      old_subscription: @subscription,
      new_subscription: @new_subscription
    )

    if result.success?
      if admin?
        flash[:success] = "Membership updated."
        turbolinks_redirect(user_path(@subscription.subscribable))
      else
        flash[:success] = "Your membership has been updated"
        turbolinks_redirect(home_path)
      end
    else
      flash[:error] = result.message
      turbolinks_redirect(referrer_or_root)
    end
  rescue Exception => e
    Rollbar.error(e)
    flash[:error] = "An error occurred: #{e.message}"
    turbolinks_redirect(referrer_or_root)
  end

  def destroy
    find_subscription
    authorize @subscription

    result = CancelSubscription.call(
      subscription: @subscription
    )

    if result.success?
      flash[:success] = "Membership cancelled."
      turbolinks_redirect(referrer_or_root)
    else
      flash[:error] = result.message
      turbolinks_redirect(referrer_or_root)
    end
  rescue Exception => e
    Rollbar.error(e)
    flash[:error] = "An error occurred: #{e.message}"
    turbolinks_redirect(referrer_or_root)
  end

  private

  def subscription_params
    params.require(:subscription).permit(:plan_id)
  end

  def admin_subscription_params
    params.require(:subscription).permit(:plan_id, :user_id)
  end

  def find_subscription(key=:id)
    @subscription = Subscription.find(params[key])
  end

  def new_subscription
    subscription = Subscription.new(subscription_params)
    subscription.subscribable = current_user
    subscription.active = true
    subscription
  end

  def new_admin_subscription
    subscription = Subscription.new(admin_subscription_params)
    subscription.active = true
    subscription
  end
end
