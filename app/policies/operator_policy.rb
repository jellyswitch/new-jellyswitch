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
end