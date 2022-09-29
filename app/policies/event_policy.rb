
class EventPolicy < ApplicationPolicy
  def index?
    enabled?
  end

  def past?
    enabled?
  end

  def new?
    enabled? && (admin? || community_manager? || general_manager?)
  end

  def create?
    enabled? && (admin? || community_manager? || general_manager?)
  end

  def show?
    enabled?
  end

  def edit?
    enabled? && (admin? || community_manager? || general_manager?)
  end

  def update?
    enabled? && (admin? || community_manager? || general_manager?)
  end

  def destroy?
    enabled? && (admin? || community_manager? || general_manager?)
  end

  def rsvp?
    enabled? && future?
  end
  
  def future?
    record.starts_at >= Time.current
  end

  def enabled?
    operator.events_enabled?
  end
end