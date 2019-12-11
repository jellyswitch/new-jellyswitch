# typed: true
class PlanPolicy < ApplicationPolicy
  def index?
    admin?
  end

  def archived?
    admin?
  end

  def show?
    admin?
  end

  def edit?
    admin?
  end

  def new?
    admin?
  end

  def create?
    admin?
  end

  def update?
    admin?
  end

  def destroy?
    admin?
  end

  def unarchive?
    admin?
  end

  def toggle_visibility?
    admin?
  end

  def toggle_availability?
    admin?
  end

  def toggle_building_access?
    admin?
  end
end