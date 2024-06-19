class ReservationPolicy < ApplicationPolicy
  def new?
    (admin? || community_manager? || general_manager? || ((user.allowed_in?(location) && approved?) || billing_disabled?))
  end

  def create?
    (admin? || community_manager? || general_manager? || ((user.allowed_in?(location) && approved?) || billing_disabled?))
  end

  def show?
    (admin? || owner? || community_manager? || general_manager?)
  end

  def destroy?
    (admin_or_manager? || (owner? && !record.room.paid_room?)) && upcoming_reservation?
  end

  def cancel?
    (admin_or_manager? || owner?) && upcoming_reservation?
  end

  def long_duration?
    (admin? || community_manager? || general_manager?)
  end

  def today?
    (admin? || community_manager? || general_manager?)
  end

  def choose_member?
    (admin? || community_manager? || general_manager?)
  end

  private

  def admin_or_manager?
    admin? || community_manager? || general_manager?
  end

  def upcoming_reservation?
    record.future? || record.ongoing?
  end
end
