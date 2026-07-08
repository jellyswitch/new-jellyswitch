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

  # Role gate only. The "must have a card on file" precondition is handled in
  # the controller so a card-less org gets redirected to add one instead of a
  # generic "not allowed" denial.
  def credit_card?
    (admin? || user.organization_owner? || superadmin? || community_manager? || general_manager?)
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
    user.superadmin? && !record.has_active_lease? && !record.has_active_subscriptions? && record.subscriptions.active.empty?
  end

  # WRITE actions (add/remove members, change billing) — deliberately tighter
  # than the members?/billing? READ gates. Those admit user.organization_owner?
  # (owns ANY org), fine for viewing but it must NOT let the owner of one org
  # mutate another. A write requires staff OR ownership of THIS organization
  # (record), mirroring the mobile API's org.owner_id == user.id. Before these
  # existed, Operator::OrganizationMembersController#create and
  # Operator::OrganizationBillingController#create had only require_authentication
  # and never authorized, so any member could reassign org membership or change
  # any org's billing / out_of_band flag.
  def manage_members?
    organization_staff? || owns_this_organization?
  end

  def manage_billing?
    organization_staff? || owns_this_organization?
  end

  private

  def organization_staff?
    admin? || community_manager? || general_manager? || superadmin?
  end

  def owns_this_organization?
    is_user? && record.owner_id.present? && record.owner_id == user.id
  end
end
