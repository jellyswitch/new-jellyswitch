
class DayPassTypePolicy < ApplicationPolicy
  def index?
    (admin? || community_manager? || general_manager?) && billing_enabled?
  end

  def show?
    (admin? || community_manager? || general_manager?) && billing_enabled?
  end

  def edit?
    (admin? || general_manager?) && billing_enabled?
  end

  def new?
    (admin? || general_manager?) && billing_enabled?
  end

  def create?
    (admin? || general_manager?) && billing_enabled?
  end

  def update?
    (admin? || general_manager?) && billing_enabled?
  end

  def destroy?
    (admin? || general_manager?) && billing_enabled?
  end
end