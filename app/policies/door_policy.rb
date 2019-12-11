# typed: true
class DoorPolicy < ApplicationPolicy
  def index?
    admin?
  end

  def show?
    admin?
  end

  def new?
    admin?
  end

  def create?
    admin?
  end

  def update?
    admin?
  end

  def edit?
    admin?
  end

  def open?
    admin? || (user.allowed_in?(location) && approved?)
  end

  def keys?
    admin? || (user.allowed_in?(location) && approved?)
  end
end