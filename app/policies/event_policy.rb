# typed: true
class EventPolicy < ApplicationPolicy
  def index?
    true
  end

  def past?
    true
  end

  def new?
    admin?
  end

  def create?
    admin?
  end

  def show?
    true  
  end

  def edit?
    admin?
  end

  def update?
    admin?
  end

  def destroy?
    admin?
  end

  def rsvp?
    record.starts_at >= Time.current
  end
end