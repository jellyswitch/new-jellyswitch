
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

  # Pause / unpause are owner-management actions like cancel — a member may
  # suspend their own month-to-month membership (travel, etc.) and staff may
  # act on a member's. Before this existed, Operator::PauseMembershipsController
  # never authorized at all and did a global Subscription.find(params[:id]),
  # so any authenticated member could pause/unpause ANY subscription by id
  # (cross-member, even cross-tenant — Subscription is not tenant-scoped).
  def pause?
    (admin? || general_manager? || (owner? && approved? && billing_enabled?))
  end

  def unpause?
    (admin? || general_manager? || (owner? && approved? && billing_enabled?))
  end

  private

  def owner?
    is_user? && (user == record.subscribable)
  end
end