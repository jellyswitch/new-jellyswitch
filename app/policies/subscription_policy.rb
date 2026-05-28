
class SubscriptionPolicy < ApplicationPolicy
  def index?
    is_user? && billing_enabled?
  end

  def new?
    is_user? && billing_enabled?
  end

  def create?
    is_user?  && billing_enabled?
  end

  def confirm?
    is_user?  && billing_enabled?
  end

  # Owner-management actions (edit / update / destroy /
  # destroy_subscription_now) used to also require `user.member?(location)`
  # — that predicate now returns false for paused subscriptions
  # (PR #466), which meant a paused owner couldn't even reach the
  # controller to switch plans or cancel. Pundit would deny first and
  # the user got the generic "Whoops!" flash instead of the actionable
  # "your membership is paused, unpause first" message the controller
  # is set up to return. The owner+approved+billing_enabled gate is
  # enough: you own the sub, you can manage it.
  def edit?
    (admin? || general_manager? || (owner? && approved? && billing_enabled?))
  end

  def update?
    (admin? || general_manager? || (owner? && approved? && billing_enabled?))
  end

  def destroy?
    (admin? || general_manager? || (owner? && approved? && billing_enabled?))
  end

  def destroy_subscription_now?
    (admin? || general_manager? || (owner? && approved? && billing_enabled?))
  end

  private

  def owner?
    is_user? && (user == record.subscribable)
  end
end