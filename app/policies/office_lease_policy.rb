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
    location.offices_enabled?
  end

  def renewal?
    enabled? && (admin? || community_manager? || general_manager?) && record.eligible_for_renewal?
  end

  def edit_price?
    update_price?
  end

  def update_price?
    enabled? && admin_or_manager? && record.active? && record.subscription_active?
  end

  private

  def owner?
    record.organization.owner == user
  end
end
