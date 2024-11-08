class OfficePolicy < ApplicationPolicy
  def index?
    enabled? && (admin? || superadmin? || general_manager?)
  end

  def show?
    enabled? && (admin? || superadmin? || general_manager?)
  end

  def new?
    enabled? && (admin? || superadmin? || general_manager?)
  end

  def create?
    enabled? && (admin? || superadmin? || general_manager?)
  end

  def edit?
    enabled? && (admin? || superadmin? || general_manager?)
  end

  def update?
    enabled? && (admin? || superadmin? || general_manager?)
  end

  def available?
    enabled? && (admin? || superadmin? || general_manager?)
  end

  def upcoming_renewals?
    enabled? && (admin? || superadmin? || general_manager?)
  end

  def archived?
    enabled? && (admin? || superadmin? || general_manager?)
  end

  def enabled?
    location.offices_enabled?
  end

  def destroy?
    enabled? && (user.superadmin?) && !record.has_active_lease?
  end
end
