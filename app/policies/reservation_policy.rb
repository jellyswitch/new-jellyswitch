# typed: true
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
    (admin? || community_manager? || general_manager? || ((user.allowed_in?(location) && approved?) || billing_disabled?))
  end

  def cancel?
    (admin? || community_manager? || general_manager? || (owner? && future?))
  end

  def long_duration?
    (admin? || community_manager? || general_manager?)
  end

  def today?
    (admin? || community_manager? || general_manager?)
  end

  private

  def future?
    record.datetime_in > Time.zone.now
  end
end