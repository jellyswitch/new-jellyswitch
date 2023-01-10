class OfficeLeasePolicy < ApplicationPolicy
  def index?
    enabled? && (admin? || community_manager? || general_manager?)
  end

  def show?
    enabled? && (admin? || owner? || community_manager? || general_manager?)
  end

  def new?
    enabled? && (admin? || community_manager? || general_manager?)
  end

  def create?
    enabled? && (admin? || community_manager? || general_manager?)
  end

  def destroy?
    enabled? && (admin? || community_manager? || general_manager?)
  end

  def destroy_office_lease_now?
    enabled? && (admin? || owner? || community_manager? || general_manager?)
  end

  def enabled?
    operator.offices_enabled?
  end

  private

  def owner?
    record.organization.owner == user
  end
end
