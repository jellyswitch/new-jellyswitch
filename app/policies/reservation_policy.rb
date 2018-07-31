class ReservationPolicy < ApplicationPolicy
  def new?
    admin_or_member?
  end

  def create?
    admin_or_member?
  end

  def show?
    admin_or_member?
  end

  def destroy?
    owner_or_admin?
  end
end