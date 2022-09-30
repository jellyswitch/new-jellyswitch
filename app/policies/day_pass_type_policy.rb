
class DayPassTypePolicy < ApplicationPolicy
  def index?
    (admin? || community_manager? || general_manager?) && billing_enabled?
  end

  def show?
    (admin? || community_manager? || general_manager?) && billing_enabled?
  end

  def edit?
    (admin? || community_manager? || general_manager?) && billing_enabled?
  end

  def new?
    (admin? || community_manager? || general_manager?) && billing_enabled?
  end

  def create?
    (admin? || community_manager? || general_manager?) && billing_enabled?
  end

  def update?
    (admin? || community_manager? || general_manager?) && billing_enabled?
  end

  def destroy?
    (admin? || community_manager? || general_manager?) && billing_enabled?
  end
end