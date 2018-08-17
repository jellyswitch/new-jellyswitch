module SubscriptionsHelper
  def ensure_subscribed
    if member? && !approved?
      redirect_to wait_path
    else
      unless admin?
        flash[:warning] = "You must be a member to do that."
        redirect_to new_subscription_path
      end
    end
  end
end