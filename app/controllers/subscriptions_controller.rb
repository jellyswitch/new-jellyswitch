class SubscriptionsController < ApplicationController
  def new
    @subscription = Subscription.new
    authorize @subscription
    background_image
    include_stripe
  end

  def create
    @subscription = new_subscription
    authorize @subscription

    token = params[:stripeToken]
    current_user.ensure_stripe_customer(token)
    if @subscription.save
      flash[:success] = "Welcome to #{Rails.application.config.x.customization.name}!"
      redirect_to root_path
    else
      flash[:error] = "An error occurred."
      render :new
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
    
    @subscription.active = false
    @new_subscription = new_subscription
    @new_subscription.user = @subscription.user # in case this is an admin

    if @new_subscription.save
      if @subscription.save
        flash[:notice] = "Your membership has been updated."
        redirect_to root_path
      else
        flash[:error] = "An error occurred."
        render :edit  
      end
    else
      flash[:error] = "An error occurred."
      render :edit
    end
  end

  def destroy
    find_subscription
    authorize @subscription

    @subscription.active = false
    if @subscription.save
      redirect_to home_path
    else
      flash[:error] = "An error occurred."
      redirect_to user_memberships_path(@subscription.user)
    end
  end

  private

  def subscription_params
    params.require(:subscription).permit(:plan_id)
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
end