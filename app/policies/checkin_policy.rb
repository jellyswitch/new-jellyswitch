
class CheckinPolicy < ApplicationPolicy
  def new?
    true
  end

  def required?
    true
  end

  def create?
    true
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