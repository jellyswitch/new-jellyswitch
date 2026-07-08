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

  # Terminating a lease early is a staff-only action — we do let members out of
  # leases (e.g. when demand is high), but that's an admin's call, not something
  # a member presses themselves. The `owner?` clause (a non-staff organization
  # owner) was removed: it let the company point-of-contact self-terminate the
  # lease (cancel the Stripe sub + set end_date=today) from the web, which every
  # sibling lease action (destroy?/renew?) and the mobile admin API already
  # forbid. Matches the "don't let people out of long-term agreements unless an
  # admin does it" rule.
  def destroy_office_lease_now?
    enabled? && (admin? || general_manager?)
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
