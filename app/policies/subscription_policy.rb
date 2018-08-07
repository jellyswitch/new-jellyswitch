class SubscriptionPolicy < ApplicationPolicy
  def new?
    is_user?
  end

  def create?
    is_user?
  end
end