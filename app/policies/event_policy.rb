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
    member? || admin?
  end

  def edit?
    admin?
  end

  def update?
    admin?
  end

  def rsvp?
    member? || admin?
  end
end