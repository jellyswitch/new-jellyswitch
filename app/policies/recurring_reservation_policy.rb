class RecurringReservationPolicy < ApplicationPolicy
  def index?
    admin_or_manager?
  end

  def show?
    admin_or_manager?
  end

  def new?
    admin_or_manager?
  end

  def create?
    admin_or_manager?
  end

  # Conflict preview on the new-series form; same rule as create?.
  def check_conflicts?
    admin_or_manager?
  end

  def cancel_series?
    admin_or_manager?
  end

  def cancel_occurrence?
    admin_or_manager?
  end

  private

  def admin_or_manager?
    admin? || community_manager? || general_manager? || superadmin?
  end
end
