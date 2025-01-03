
class CheckinPolicy < ApplicationPolicy
  def new?
    is_user?
  end

  def required?
    true
  end

  def create?
    is_user?
  end

  def show?
    (admin? || community_manager? || general_manager?)
  end

  def index?
    (admin? || community_manager? || general_manager?)
  end

  def destroy?
    (owner? || admin? || community_manager? || general_manager?)
  end
end