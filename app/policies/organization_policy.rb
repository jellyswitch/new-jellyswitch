class OrganizationPolicy < ApplicationPolicy
  def index?
    (admin? || superadmin? || community_manager? || general_manager?)
  end

  def show?
    (admin? || user.organization_owner? || superadmin? || community_manager? || general_manager?)
  end

  def new?
    (admin? || superadmin? || community_manager? || general_manager?)
  end

  def create?
    (admin? || superadmin? || community_manager? || general_manager?)
  end

  def edit?
    (admin? || user.organization_owner? || superadmin? || community_manager? || general_manager?)
  end

  def update?
    (admin? || superadmin? || community_manager? || general_manager?)
  end

  def credit_card?
    (admin? || user.organization_owner? || superadmin? || community_manager? || general_manager?) && record.card_added?
  end

  def out_of_band?
    (admin? || community_manager? || superadmin? || general_manager? || user.organization_owner?)
  end

  def billing?
    (admin? || community_manager? || superadmin? || general_manager? || user.organization_owner?)
  end

  def payment_method?
    (admin? || community_manager? || superadmin? || general_manager? || user.organization_owner?)
  end

  def members?
    (admin? || community_manager? || superadmin? || general_manager? || user.organization_owner?)
  end

  def leases?
    (admin? || community_manager? || superadmin? || general_manager? || user.organization_owner?)
  end

  def invoices?
    (admin? || community_manager? || superadmin? || general_manager? || user.organization_owner?)
  end

  def ltv?
    (admin? || community_manager? || superadmin? || general_manager?)
  end

  def destroy?
    user.admin_or_manager? && !record.has_active_lease? && !record.has_active_subscriptions? && record.subscriptions.active.empty?
  end
end
