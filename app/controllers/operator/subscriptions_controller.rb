class Operator::SubscriptionsController < Operator::ApplicationController
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

    result = CreateSubscription.call(
      subscription: @subscription,
      token: params[:stripeToken],
      user: @subscription.user
    )

    if result.success?
      flash[:success] = "Welcome to #{Rails.application.config.x.customization.name}!"
      redirect_to root_path
    else
      flash[:error] = result.message
      redirect_to referrer_or_root
    end
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
      flash[:success] = "Your membership has been updated"
      redirect_to home_path
    else
      flash[:error] = result.message
      redirect_to referrer_or_root
    end
  end

  def destroy
    find_subscription
    authorize @subscription

    result = CancelSubscription.call(
      subscription: @subscription
    )

    if result.success?
      flash[:success] = "Membership cancelled."
      redirect_to home_path
    else
      flash[:error] = result.message
      redirect_to referrer_or_root
    end
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
    subscription.user = current_user
    subscription.active = true
    subscription
  end

  def new_admin_subscription
    subscription = Subscription.new(admin_subscription_params)
    subscription.active = true
    subscription
  end
end