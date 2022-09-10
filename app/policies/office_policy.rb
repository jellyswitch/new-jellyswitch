# typed: true
class OfficePolicy < ApplicationPolicy
  def index?
    enabled? && (admin? || superadmin? || community_manager? || general_manager?)
  end

  def show?
    enabled? && (admin? || superadmin? || community_manager? || general_manager?)
  end

  def new?
    enabled? && (admin? || superadmin? || community_manager? || general_manager?)
  end

  def create?
    enabled? && (admin? || superadmin? || community_manager? || general_manager?)
  end

  def edit?
    enabled? && (admin? || superadmin? || community_manager? || general_manager?)
  end

  def update?
    enabled? && (admin? || superadmin? || community_manager? || general_manager?)
  end

  def available?
    enabled? && (admin? || superadmin? || community_manager? || general_manager?)
  end

  def upcoming_renewals?
    enabled? && (admin? || superadmin? || community_manager? || general_manager?)
  end

  def enabled?
    operator.offices_enabled?
  end
end
