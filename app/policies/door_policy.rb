class DoorPolicy < ApplicationPolicy
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

  def destroy?
    enabled? && (admin? || general_manager?)
  end

  def archived?
    enabled? && (admin? || community_manager? || general_manager?)
  end

  def unarchive?
    enabled? && (admin? || general_manager?)
  end

  def edit?
    enabled? && (admin? || general_manager?)
  end

  def open?
    user.present? && (admin? || community_manager? || general_manager? || (user.allowed_in?(location) && approved?) || billing_disabled?)
  end

  def keys?
    user.present? && (admin? || community_manager? || general_manager? || (user.allowed_in?(location) && approved?) || billing_disabled?)
  end

  def enabled?
    # Nil-safe: anonymous users (or admins on a multi-location operator who
    # haven't picked a location yet) reach the operator nav layout with
    # `location` unset. Treat absent location as "feature off" so the nav
    # render doesn't 500.
    location&.door_integration_enabled? || false
  end
end
