class OperatorPolicy < ApplicationPolicy
  def index?
    superadmin?
  end

  def new?
    superadmin?
  end

  def show?
    superadmin?
  end

  def edit?
    superadmin?
  end

  def update?
    superadmin?
  end

  def create?
    superadmin?
  end

  def demo_instance?
    superadmin?
  end

  def destroy?
    superadmin?
  end
end