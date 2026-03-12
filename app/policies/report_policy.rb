class ReportPolicy < ApplicationPolicy
  def index?
    (admin? || superadmin? || general_manager?)
  end

  def member_csv?
    (admin? || superadmin? || general_manager?)
  end

  def active_lease_members?
    (admin? || superadmin? || general_manager?)
  end

  def active_members?
    (admin? || superadmin? || general_manager?)
  end

  def active_leases?
    (admin? || superadmin? || general_manager?)
  end

  def last_30_day_passes?
    (admin? || superadmin? || general_manager?)
  end

  def total_members?
    (admin? || superadmin? || general_manager?)
  end

  def membership_breakdown?
    (admin? || superadmin? || general_manager?)
  end

  def revenue?
    (admin? || superadmin? || general_manager?)
  end

  def checkins?
    (admin? || superadmin? || general_manager?)
  end

  def monetization?
    (admin? || superadmin? || general_manager?)
  end

  def ltv?
    (admin? || superadmin? || general_manager?)
  end
end