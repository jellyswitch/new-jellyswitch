# typed: true
class ReservationPolicy < ApplicationPolicy
  def new?
    admin? || (member? && approved?)
  end

  def create?
    admin? || (member? && approved?)
  end

  def show?
    admin? || owner?
  end

  def destroy?
    (member? && approved? && owner?) || admin?
  end

  def cancel?
    admin? || (owner? && future?)
  end

  private

  def future?
    record.datetime_in > Time.zone.now
  end
end