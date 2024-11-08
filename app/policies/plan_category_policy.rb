class PlanCategoryPolicy < ApplicationPolicy

  def index?
    can_see?
  end

  def new?
    can_see?
  end

  def show?
    can_see?
  end

  def create?
    can_see?
  end

  def update?
    can_see?
  end

  def destroy?
    can_see?
  end

  def remove_plan?
    can_see?
  end

  private

  def can_see?
    ( admin? || general_manager? )
  end
end