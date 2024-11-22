
class PlanPolicy < ApplicationPolicy
  def index?
    (admin? || general_manager?) && billing_enabled?
  end

  def archived?
    (admin? || general_manager?) && billing_enabled?
  end

  def show?
    (admin? || general_manager?) && billing_enabled?
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

  def unarchive?
    (admin? || general_manager?) && billing_enabled?
  end

  def toggle_visibility?
    (admin? || general_manager?) && billing_enabled?
  end

  def toggle_availability?
    (admin? || general_manager?) && billing_enabled?
  end

  def toggle_building_access?
    (admin? || general_manager?) && billing_enabled?
  end
end