class OfficeLeasePolicy < ApplicationPolicy
  def index?
    enabled? && (admin? || general_manager?)
  end

  def show?
    enabled? && (admin? || owner? || general_manager?)
  end

  def new?
    enabled? && (admin? || general_manager?)
  end

  def create?
    enabled? && (admin? || general_manager?)
  end

  def destroy?
    enabled? && (admin? || general_manager?)
  end

  def destroy_office_lease_now?
    enabled? && (admin? || owner? || general_manager?)
  end

  def enabled?
    # Nil-safe; see DoorPolicy#enabled? for the rationale.
    location&.offices_enabled? || false
  end

  def renewal?
    enabled? && (admin? || general_manager?) && record.eligible_for_renewal?
  end

  def edit_price?
    update_price?
  end

  def update_price?
    enabled? && (admin? || general_manager?) && record.active? && record.subscription_active?
  end

  def convert_to_organization?
    enabled? && (admin? || general_manager?) && record.individual_lease? && record.active?
  end

  def charge_deposit?
    enabled? && (admin? || general_manager?)
  end

  def mark_deposit_invoiced?
    charge_deposit?
  end

  private

  def owner?
    record.organization.present? && record.organization.owner == user
  end
end
