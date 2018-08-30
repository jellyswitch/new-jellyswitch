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
    admin? || (approved? && member?)
  end

  def keys?
    admin? || (approved? && member?)
  end
end