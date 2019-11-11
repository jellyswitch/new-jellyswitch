# typed: true
class EventPolicy < ApplicationPolicy
  def index?
    member? || admin?
  end

  def past?
    member? || admin?
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

  def rsvp?
    record.starts_at >= Time.current
  end
end