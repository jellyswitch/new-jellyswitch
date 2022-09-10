# typed: true
class OfficeLeasePolicy < ApplicationPolicy
  def index?
    enabled? && (admin? || superadmin? || community_manager? || general_manager?)
  end

  def show?
    enabled? && (admin? || owner? || superadmin? || community_manager || general_manager?)
  end

  def new?
    enabled? && (admin? || owner? || superadmin? || community_manager || general_manager?)
  end

  def create?
    enabled? && (admin? || owner? || superadmin? || community_manager || general_manager?)
  end

  def destroy?
    enabled? && (admin? || owner? || superadmin? || community_manager || general_manager?)
  end

  def enabled?
    operator.offices_enabled?
  end

  private

  def owner?
    record.organization.owner == user
  end
end
