# typed: true
class DayPassTypePolicy < ApplicationPolicy
  def index?
    admin? && billing_enabled?
  end

  def show?
    admin? && billing_enabled?
  end

  def edit?
    false # We don't want to edit day passes for accounting purposes
  end

  def new?
    admin? && billing_enabled?
  end

  def create?
    admin? && billing_enabled?
  end

  def update?
    admin? && billing_enabled?
  end

  def destroy?
    admin? && billing_enabled?
  end
end