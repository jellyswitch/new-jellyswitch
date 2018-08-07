class SubscriptionPolicy < ApplicationPolicy
  def new?
    is_user?
  end

  def create?
    is_user?
  end

  def edit?
    owner_or_admin?
  end

  def update?
    owner_or_admin?
  end
end