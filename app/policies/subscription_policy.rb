# typed: true
class SubscriptionPolicy < ApplicationPolicy
  def new?
    is_user?
  end

  def create?
    is_user?
  end

  def edit?
    admin? || (owner? && user.member?(location) && approved?)
  end

  def update?
    admin? || (owner? && user.member?(location) && approved?)
  end

  def destroy?
    admin? || (owner? && user.member?(location) && approved?)
  end

  private

  def owner?
    is_user? && (user == record.subscribable)
  end
end