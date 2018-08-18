class ReservationPolicy < ApplicationPolicy
  def new?
    admin? || (member? && approved?)
  end

  def create?
    admin? || (member? && approved?)
  end

  def show?
    admin? || (member? && approved?)
  end

  def destroy?
    (member? && approved? && owner?) || admin?
  end
end