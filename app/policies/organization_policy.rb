# typed: true
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

  def destroy?
    (admin? || superadmin? || community_manager? || general_manager?)
  end

  def credit_card?
    (admin? || user.organization_owner? || superadmin? || community_manager? || general_manager?) && record.card_added?
  end

  def out_of_band?
    admin? || user.organization_owner?
  end

  def billing?
    admin? || user.organization_owner?
  end

  def payment_method?
    admin? || user.organization_owner?
  end

  def members?
    admin? || user.organization_owner?
  end

  def leases?
    admin? || user.organization_owner?
  end

  def invoices?
    admin? || user.organization_owner?
  end

  def ltv?
    admin?
  end
end
