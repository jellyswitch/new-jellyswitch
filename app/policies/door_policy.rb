class DoorPolicy < ApplicationPolicy
  def index?
    enabled? && (admin? || community_manager? || general_manager?)
  end

  def show?
    enabled? && (admin? || community_manager? || general_manager?)
  end

  def new?
    enabled? && (admin? || community_manager? || general_manager?)
  end

  def create?
    enabled? && (admin? || community_manager? || general_manager?)
  end

  def update?
    enabled? && (admin? || community_manager? || general_manager?)
  end

  def destroy?
    enabled? && superadmin?
  end

  def edit?
    enabled? && (admin? || community_manager? || general_manager?)
  end

  def open?
    user.present? && (admin? || community_manager? || general_manager? || (user.allowed_in?(location) && approved?) || billing_disabled?)
  end

  def keys?
    user.present? && (admin? || community_manager? || general_manager? || (user.allowed_in?(location) && approved?) || billing_disabled?)
  end

  def enabled?
    operator.door_integration_enabled?
  end
end
