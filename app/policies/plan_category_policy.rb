class PlanCategoryPolicy < ApplicationPolicy

  def index?
    ( admin? || community_manager? || general_manager? )
  end

  def new?
    ( admin? || community_manager? || general_manager? )
  end

  def show?
    ( admin? || community_manager? || general_manager? )
  end

  def create?
    ( admin? || community_manager? || general_manager? )
  end

  def update?
    ( admin? || community_manager? || general_manager? )
  end

  def destroy?
    ( admin? || community_manager? || general_manager? )
  end

  def remove_plan?
    ( admin? || community_manager? || general_manager? )
  end
end