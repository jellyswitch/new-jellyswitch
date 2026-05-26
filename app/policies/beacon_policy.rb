class BeaconPolicy < ApplicationPolicy
  def index?
    enabled? && (admin? || community_manager? || general_manager?)
  end

  def show?
    enabled? && (admin? || community_manager? || general_manager?)
  end

  def new?
    enabled? && (admin? || general_manager?)
  end

  def create?
    enabled? && (admin? || general_manager?)
  end

  def update?
    enabled? && (admin? || general_manager?)
  end

  def edit?
    enabled? && (admin? || general_manager?)
  end

  def destroy?
    enabled? && (admin? || general_manager?)
  end

  def enabled?
    location&.door_integration_enabled? || false
  end
end
