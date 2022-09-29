
class PlanPolicy < ApplicationPolicy
  def index?
    (admin? || community_manager? || general_manager?) && billing_enabled?
  end

  def archived?
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

  def unarchive?
    (admin? || community_manager? || general_manager?) && billing_enabled?
  end

  def toggle_visibility?
    (admin? || community_manager? || general_manager?) && billing_enabled?
  end

  def toggle_availability?
    (admin? || community_manager? || general_manager?) && billing_enabled?
  end

  def toggle_building_access?
    (admin? || community_manager? || general_manager?) && billing_enabled?
  end
end