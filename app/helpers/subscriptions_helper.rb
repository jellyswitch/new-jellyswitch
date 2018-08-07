module SubscriptionsHelper
  def ensure_subscribed
    unless current_user.member? || current_user.admin?
      flash[:warning] = "You must be a member to do that."
      redirect_to new_subscription_path
    end
  end
end