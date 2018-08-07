class SubscriptionsController < ApplicationController
  def new
    @subscription = Subscription.new
    authorize @subscription
  end

  def create
    @subscription = Subscription.new(subscription_params)
    @subscription.user = current_user
    @subscription.active = true
    authorize @subscription

    if @subscription.save
      flash[:notice] = "You've successfully subscribed."
      redirect_to root_path
    else
      flash[:error] = "Error subscribing"
      render :new
    end
  end

  private

  def subscription_params
    params.require(:subscription).permit(:plan_id)
  end
end