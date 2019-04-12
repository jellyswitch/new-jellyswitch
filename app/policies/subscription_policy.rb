class SubscriptionPolicy < ApplicationPolicy
  def new?
    is_user?
  end

  def create?
    is_user?
  end

  def edit?
    admin? || (owner? && member? && approved?)
  end

  def update?
    admin? || (owner? && member? && approved?)
  end

  def destroy?
    admin? || (owner? && member? && approved?)
  end

  private

  def owner?
    is_user? && (user == record.subscribable)
  end
end