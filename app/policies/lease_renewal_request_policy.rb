class LeaseRenewalRequestPolicy < ApplicationPolicy
  def show?
    admin? || general_manager? || leasee?
  end

  def accept?
    leasee? && record.pending_leasee?
  end

  def request_modification?
    leasee? && record.pending_leasee?
  end

  def index?
    admin? || general_manager?
  end

  def admin_review?
    admin? || general_manager?
  end

  def admin_approve?
    (admin? || general_manager?) && record.pending?
  end

  def admin_decline?
    (admin? || general_manager?) && record.pending?
  end

  def admin_force_approve?
    (admin? || general_manager?) && record.pending?
  end

  private

  def leasee?
    lease = record.office_lease
    if lease.individual_lease?
      user == lease.user
    elsif lease.organization.present?
      user == lease.organization.owner
    else
      false
    end
  end
end
