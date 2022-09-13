# typed: true
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

  def edit?
    (admin? || community_manager? || general_manager? || (owner? && user.member?(location) && approved? && billing_enabled?))
  end

  def update?
    (admin? || community_manager? || general_manager? || (owner? && user.member?(location) && approved? && billing_enabled?))
  end

  def destroy?
    (admin? || community_manager? || general_manager? || (owner? && user.member?(location) && approved? && billing_enabled?))
  end

  private

  def owner?
    is_user? && (user == record.subscribable)
  end
end