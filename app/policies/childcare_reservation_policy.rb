class ChildcareReservationPolicy < ApplicationPolicy
  def index?
    enabled? && admin?
  end

  def new?
    enabled?
  end

  def create?
    enabled?
  end

  def show?
    enabled? && admin_or_owner?
  end

  def destroy?
    enabled? && admin_or_owner?
  end

  def enabled?
    operator.childcare_enabled?
  end

  private

  def admin_or_owner?
    admin? || record.child_profile.user == user
  end
end