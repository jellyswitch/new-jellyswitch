class DayPassTypePolicy < ApplicationPolicy
  def index?
    admin?
  end

  def show?
    admin?
  end

  def edit?
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

  def destroy?
    admin?
  end
end